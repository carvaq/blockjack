// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title TODO
/// @author TODO
/// @notice TODO
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

    address[] private players;
    mapping(address => Card[]) private hands;
    mapping(address => PlayerStatus) private playerStatus;
    Phase public phase;

    constructor(uint _roundSessionExpiryInSeconds) {
        dealer = msg.sender;
        roundSessionExpiryInSeconds = _roundSessionExpiryInSeconds;
        phase = Phase.PlaceBets;
    }

    function getHand() public view returns (Card[] memory)  {
        return hands[msg.sender];
    }

    function placeBet() public {
        require(msg.sender == dealer, "Dealer cannot place bets.");
        require(phase == Phase.PlaceBets, "Not taking any new players.");
        require(playerStatus[msg.sender] == PlayerStatus.NotPlaying, "Player is already in the game.");

        players.push(msg.sender);
        playerStatus[msg.sender] = PlayerStatus.NeedsToDecide;
    }

    function deal() public {
        require(msg.sender == dealer, "Only the dealer can deal.");
        require(
            block.timestamp >= currentRoundTimeout,
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
            dealerReveal();
        }

        if (phase == Phase.HitOrStand) {
            currentRoundTimeout = block.timestamp + roundSessionExpiryInSeconds;
        } else if (phase == Phase.DealersBust) {
            resetState();
        } else if (phase == Phase.PlayersBust) {
            resetState();
        }
    }

    function hit() public {
        require(
            playerStatus[msg.sender] != PlayerStatus.Stand,
            "Player already selected stand once."
        );
        decide(PlayerStatus.Hit);
        emit Hit(msg.sender);
    }

    function stand() public {
        require(
            playerStatus[msg.sender] != PlayerStatus.Hit,
            "Player already selected hit once."
        );
        decide(PlayerStatus.Stand);
        emit Stand(msg.sender);
    }

    function decide(PlayerStatus status) private {
        require(
            playerStatus[msg.sender] != PlayerStatus.NotPlaying,
            "Only player can hit or stand."
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

    function dealInitialHand() private {
        for (uint i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            hands[playerAddress].push(getCard());
            hands[playerAddress].push(getCard());
        }

        hands[dealer].push(getCard());
    }

    function handleRoundForPlayers() private {
        uint playersThatCanContinuePlaying = players.length;
        for (uint i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            PlayerStatus status = playerStatus[playerAddress];
            if (status == PlayerStatus.Hit) {
                dealCardToPlayer(playerAddress);
            } else if (status == PlayerStatus.NeedsToDecide) {
                // handle the case the player missed the opportunity to decide on hit or stand
                emit Stand(playerAddress);
                playerStatus[playerAddress] = PlayerStatus.Stand;
            }

            if (playerStatus[playerAddress] == PlayerStatus.Stand) {
                //players that will no longer be able to play have the status PlayerStatus.Stand
                playersThatCanContinuePlaying -= 1;
            }
        }
        if (playersThatCanContinuePlaying == 0) {
            phase = Phase.PlayersBust;
        }
    }


    function dealCardToPlayer(address playerAddress) private {
        hands[playerAddress].push(getCard());
        // sum of player cards is higher than BLACK_JACK
        if (sumOfHand(hands[playerAddress]) > BLACK_JACK) {
            emit Bust(playerAddress);
            playerStatus[playerAddress] = PlayerStatus.Stand;
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
                emit Bust(dealer);
                phase = Phase.DealersBust;
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
        DealersBust
    }

    enum PlayerStatus {
        NotPlaying,
        NeedsToDecide,
        Hit,
        Stand
    }
}
