// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

contract BlockJack {
    uint8 private constant ZERO_INDEX_SHIFT = 1;
    uint8 private constant MAX_CARD_VALUE = 10;
    uint8 private constant BLACK_JACK = 21;
    uint8 private constant DEALER_DECISION = 17;
    uint8 private constant  NUMBER_OF_CARDS = 13;
    uint private roundSessionExpiryInSeconds;
    address public dealer;
    uint private currentRoundTimeout;

    event Hit(address indexed player);
    event Stand(address indexed player);
    event Bust(address indexed player);
    event Win(address indexed player);

    address[] private players;
    mapping(address => Card[]) private hands;
    mapping(address => PlayerStatus) private playerStatus;
    Phase public phase;

    constructor(uint _roundSessionExpiryInSeconds) {
        dealer = msg.sender;
        roundSessionExpiryInSeconds = _roundSessionExpiryInSeconds;
        phase = Phase.PlaceBets;
    }

    function getHand() public view returns (uint[] memory)  {
        Card[] memory playerHand = hands[msg.sender];
        uint[] memory numericHand = new uint[](playerHand.length);

        for (uint i = 0; i < playerHand.length; i++) {
            numericHand[i] = uint(playerHand[i]) + ZERO_INDEX_SHIFT;
        }

        return numericHand;
    }

    function placeBet() public {
        require(msg.sender != dealer, "Dealer cannot place bets.");
        require(phase == Phase.PlaceBets, "Not taking any new players.");
        require(playerStatus[msg.sender] == PlayerStatus.NotPlaying, "Player is already in the game.");

        players.push(msg.sender);
        playerStatus[msg.sender] = PlayerStatus.NeedsToDecide;
    }

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

    function hit() public {
        decide(PlayerStatus.Hit);
        emit Hit(msg.sender);
    }

    function stand() public {
        decide(PlayerStatus.Stand);
        emit Stand(msg.sender);
    }

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

    function haveAllPlayersDecided() private view returns (bool){
        for (uint i = 0; i < players.length; i++) {
            PlayerStatus status = playerStatus[players[i]];
            if (status == PlayerStatus.NeedsToDecide) return false;
        }
        return true;
    }

    function dealInitialHand() private {
        for (uint i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            hands[playerAddress].push(getCard());
            hands[playerAddress].push(getCard());
        }

        hands[dealer].push(getCard());
    }

    function handleRoundForPlayers() private {
        uint playersBust = 0;
        uint playersStand = 0;

        for (uint i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            PlayerStatus status = playerStatus[playerAddress];

            if (status == PlayerStatus.Hit) {
                dealCardToPlayer(playerAddress);
            } else if (status == PlayerStatus.NeedsToDecide) {
                markPlayerAsStand(playerAddress);
            }

            if (playerStatus[playerAddress] == PlayerStatus.Stand) playersStand++;
            else if (playerStatus[playerAddress] == PlayerStatus.Bust) playersBust++;
        }

        updateGamePhase(playersBust, playersStand);
    }

    function markPlayerAsStand(address player) private {
        emit Stand(player);
        playerStatus[player] = PlayerStatus.Stand;
    }

    function updateGamePhase(uint playersBust, uint playersStand) private {
        if (playersBust == players.length) phase = Phase.PlayersBust;
        else if (playersBust + playersStand == players.length) phase = Phase.PlayersStand;
    }

    function dealCardToPlayer(address playerAddress) private {
        hands[playerAddress].push(getCard());
        // sum of player cards is higher than BLACK_JACK
        if (sumOfHand(hands[playerAddress]) > BLACK_JACK) {
            emit Bust(playerAddress);
            playerStatus[playerAddress] = PlayerStatus.Bust;
        } else {
            playerStatus[playerAddress] = PlayerStatus.NeedsToDecide;
        }
    }

    function dealerReveal() private {
        // dealer should only continue if there are any players to continue round
        if (phase == Phase.HitOrStand) {
            while (sumOfHand(hands[dealer]) < DEALER_DECISION) {
                hands[dealer].push(getCard());
            }
            if (sumOfHand(hands[dealer]) > BLACK_JACK) {
                notifyPlayersThatWon();
                emit Bust(dealer);
            } else {
                emit Win(dealer);
            }
        }
    }

    function notifyPlayersThatWon() private {
        for (uint i = 0; i < players.length; i++) {
            if (playerStatus[players[i]] == PlayerStatus.Stand) {
                emit Win(players[i]);
            }
        }
    }

    function getCard() private view returns (Card card) {
        return Card(getRandomNumber() % NUMBER_OF_CARDS);
    }

    function getRandomNumber() internal view returns (uint) {
        return uint(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
    }

    function sumOfHand(
        Card[] memory hand
    ) private pure returns (uint totalSum) {
        uint aceCount = 0;
        for (uint i = 0; i < hand.length; i++) {
            totalSum += Math.min(
                uint(hand[i]) + ZERO_INDEX_SHIFT,
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
        for (uint i = 0; i < players.length; i++) {
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
