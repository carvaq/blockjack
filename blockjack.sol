// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title BlockJack
 * @dev Blackjack as a smart contract.
 *
 * A round of blockjack runs in the following order:
 *  1. The owner of the contract (deployer) is the dealer. He determines the maximum amount of players.
 *  2. Players register to the game by running `placeBet()`. (currently free ;) ..)
 *  3. Dealer deals cards with `deal()`. Everyone can check their hand with `getHand()`
 *  4. Players either request an additional card with `hit()` or abstain with `stand()`
 *  5. Dealer deals additional cards to any players whi requested.
 *  6. Repeat 3. - 5. until no new requests.
 *
 */
contract BlockJack {
    uint8 private constant ZERO_INDEX_SHIFT = 1;
    uint8 private constant MAX_CARD_VALUE = 10;
    uint8 private constant BLACK_JACK = 21;
    uint8 private constant DEALER_DECISION = 17;
    uint8 private constant NUMBER_OF_CARDS = 13;

    address public dealer;
    uint8 public maxPlayers;
    Phase public phase;

    event Hit(address indexed player);
    event Stand(address indexed player);
    event Bust(address indexed player);
    event Win(address indexed player);

    uint256 private roundSessionExpiryInSeconds;
    uint256 private currentRoundTimeout;

    address[] private players;
    mapping(address => Card[]) private hands;
    mapping(address => PlayerStatus) private playerStatus;

    /**
     * @param _roundSessionExpiryInSeconds The maximum duration of a round in seconds.
     * @param _maxPlayers The maximum number of players.
     */
    constructor(uint256 _roundSessionExpiryInSeconds, uint8 _maxPlayers) {
        dealer = msg.sender;
        roundSessionExpiryInSeconds = _roundSessionExpiryInSeconds;
        maxPlayers = _maxPlayers;
        phase = Phase.PlaceBets;
    }

    /**
     * @dev Returns the hand of the calling player.
     * @return An array of uint256 representing the player's hand.
     */
    function getHand() public view returns (uint256[] memory) {
        Card[] memory playerHand = hands[msg.sender];
        uint256[] memory numericHand = new uint256[](playerHand.length);

// TODO: Update to max value
        for (uint256 i = 0; i < playerHand.length; i++) {
            numericHand[i] = uint256(playerHand[i]) + ZERO_INDEX_SHIFT;
        }

        return numericHand;
    }



    /**
     * @dev Allows a player to join the game by placing a bet.
     */
    function placeBet() public {
        require(msg.sender != dealer, "Dealer cannot place bets.");
        require(phase == Phase.PlaceBets, "Not taking any new players.");
        require(
            playerStatus[msg.sender] == PlayerStatus.NotPlaying,
            "Player is already in the game."
        );
        require(
            players.length < maxPlayers,
            "Maximum number of players reached."
        );

        players.push(msg.sender);
        playerStatus[msg.sender] = PlayerStatus.NeedsToDecide;
    }

    /**
     * @dev Deal cards to all players that want to. (`hit()`)
     */
    function deal() public {
        require(msg.sender == dealer, "Only the dealer can deal.");
        require(
            haveAllPlayersDecided() || block.timestamp >= currentRoundTimeout,
            "Current round is still running."
        );
        require(
            players.length > 0,
            "No players are registered for this round."
        );

        if (phase == Phase.PlaceBets) {
            dealInitialHand();
            phase = Phase.HitOrStand;
        } else if (phase == Phase.HitOrStand) {
            handleRoundForPlayers();
        }

        if (phase == Phase.HitOrStand) {
            currentRoundTimeout = block.timestamp + roundSessionExpiryInSeconds;
        } else if (phase == Phase.PlayersStand) {
            dealerReveal();
            resetState();
        } else if (phase == Phase.PlayersBust) {
            resetState();
        }
    }

    /**
    * @dev updates players status to hit. Allows him to request an additional card.
    */
    function hit() public {
        decide(PlayerStatus.Hit);
        emit Hit(msg.sender);
    }

    /**
    * @dev updates players status to stand. Player chooses not to receive any additional cards.
    */
    function stand() public {
        decide(PlayerStatus.Stand);
        emit Stand(msg.sender);
    }


    /**
     * @dev Handle player decision.
     * @param status The decision of the player (Hit or Stand).
     */
    function decide(PlayerStatus status) private {
        require(
            playerStatus[msg.sender] == PlayerStatus.NeedsToDecide,
            "Player cannot hit or stand currently."
        );
        require(
            phase == Phase.HitOrStand,
            "Currently not allowing hit or stand actions."
        );
        require(
            block.timestamp <= currentRoundTimeout,
            "Round does not accept any more changes."
        );

        playerStatus[msg.sender] = status;
    }

   /**
     * @return True if all players have decided.
     */
    function haveAllPlayersDecided() private view returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            PlayerStatus status = playerStatus[players[i]];
            if (status == PlayerStatus.NeedsToDecide) return false;
        }
        return true;
    }

    /**
     * @dev Deals the initial hand of two cards to each player and one card to the dealer.
     */
    function dealInitialHand() private {
        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            hands[playerAddress].push(getCard(playerAddress));
            hands[playerAddress].push(getCard(playerAddress));
        }

        hands[dealer].push(getCard(dealer));
    }

    /**
     * @dev Lets the dealer forward the round, if players don't decide. A undecided player will be interpreted as `stand`.
     */
    function handleRoundForPlayers() private {
        uint256 playersBust = 0;
        uint256 playersStand = 0;

        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            PlayerStatus status = playerStatus[playerAddress];

            if (status == PlayerStatus.Hit) {
                dealCardToPlayer(playerAddress);
            } else if (status == PlayerStatus.NeedsToDecide) {
                markPlayerAsStand(playerAddress);
            }

            if (playerStatus[playerAddress] == PlayerStatus.Stand)
                playersStand++;
            else if (playerStatus[playerAddress] == PlayerStatus.Bust)
                playersBust++;
        }

        updateGamePhase(playersBust, playersStand);
    }


    function markPlayerAsStand(address player) private {
        emit Stand(player);
        playerStatus[player] = PlayerStatus.Stand;
    }


    /**
     * @dev Updates the game phase based on the player statuses.
     * @param playersBust The number of players who have busted.
     * @param playersStand The number of players who have stood.
     */
    function updateGamePhase(uint256 playersBust, uint256 playersStand)
    private
    {
        if (playersBust == players.length) phase = Phase.PlayersBust;
        else if (playersBust + playersStand == players.length)
            phase = Phase.PlayersStand;
    }

    /**
     * @dev Deals a card to the specified player and updates their status.
     * @param playerAddress The address of the player.
     */
    function dealCardToPlayer(address playerAddress) private {
        hands[playerAddress].push(getCard(playerAddress));
        // sum of player cards is higher than BLACK_JACK
        if (sumOfHand(hands[playerAddress]) > BLACK_JACK) {
            emit Bust(playerAddress);
            playerStatus[playerAddress] = PlayerStatus.Bust;
        } else {
            playerStatus[playerAddress] = PlayerStatus.NeedsToDecide;
        }
    }


    /**
     * @dev Handles the dealer's actions and determines the outcome of the game.
     */
    function dealerReveal() private {
        // dealer should only continue if there are any players to continue round
        if (phase == Phase.HitOrStand) {
            while (sumOfHand(hands[dealer]) < DEALER_DECISION) {
                hands[dealer].push(getCard(dealer));
            }
            if (sumOfHand(hands[dealer]) > BLACK_JACK) {
                notifyPlayersThatWon();
                emit Bust(dealer);
            } else {
                emit Win(dealer);
            }
        }
    }

    /**
     * @dev Notifies all winners.
     */
    function notifyPlayersThatWon() private {
        for (uint256 i = 0; i < players.length; i++) {
            if (playerStatus[players[i]] == PlayerStatus.Stand) {
                emit Win(players[i]);
            }
        }
    }

    function getCard(address playerAddress) private view returns (Card card) {
        return Card(getRandomNumber(playerAddress) % NUMBER_OF_CARDS);
    }

    /**
     * @dev Generates a pseudo-random number based on the player's address and blockchain state.
     * @param playerAddress The address of the player.
     * @return A pseudo-random uint256.
     */
    function getRandomNumber(address playerAddress)
    internal
    view
    returns (uint256)
    {
        return
            uint256(
            keccak256(
                abi.encodePacked(
                    playerAddress,
                    block.timestamp,
                    block.number,
                    block.prevrandao,
                    blockhash(block.number - 1),
                    hands[playerAddress]
                )
            )
        );
    }

    function sumOfHand(Card[] memory hand)
    private
    pure
    returns (uint256 totalSum)
    {
        uint256 aceCount = 0;
        for (uint256 i = 0; i < hand.length; i++) {
            totalSum += Math.min(
                uint256(hand[i]) + ZERO_INDEX_SHIFT,
                MAX_CARD_VALUE
            );
            if (hand[i] == Card.Ace) aceCount++;
        }

        while (aceCount > 0 && totalSum + 10 <= BLACK_JACK) {
            totalSum += 10;
            aceCount--;
        }

        return totalSum;
    }

    function resetState() private {
        phase = Phase.PlaceBets;
        for (uint256 i = 0; i < players.length; i++) {
            delete hands[players[i]];
            playerStatus[players[i]] = PlayerStatus.NotPlaying;
        }
        delete players;
    }

    enum Card {
        Ace,
        Two,
        Three,
        Four,
        Five,
        Six,
        Seven,
        Eight,
        Nine,
        Ten,
        Jack,
        Queen,
        King
    }
    enum Phase {
        PlaceBets,
        HitOrStand,
        PlayersBust,
        PlayersStand
    }

    enum PlayerStatus {
        NotPlaying,
        NeedsToDecide,
        Bust,
        Hit,
        Stand
    }
}
