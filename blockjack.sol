// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title TODO
/// @author TODO
/// @notice TODO
contract BlockJack {
    uint256 private constant ZERO_INDEX_SHIFT = 1;
    uint256 private constant MAX_CARD_VALUE = 10;
    uint256 private constant BLACK_JACK = 21;
    uint256 private constant DEALER_DECISION = 17;
    uint16 public initialBet;
    uint16 public roundSessionExpiry;
    address public dealer;
    uint256 currentRoundTimeout;
    uint256 multiplier;
    uint8 constant NUMBER_OF_CARDS = 13;

    event Hit(address indexed player);
    event Stand(address indexed player);
    event Bust(address indexed player);

    address[] private players;
    mapping(address => Card[]) public hands;
    mapping(address => PlayerDecision) public playerDecisions;
    Phase public phase;

    mapping(Card => uint8[]) private enumValues;

    constructor(uint16 _roundSessionExpiry) {
        dealer = msg.sender;
        roundSessionExpiry = _roundSessionExpiry;
        phase = Phase.PlaceBets;
    }

    function placeBet() public payable {
        require(msg.address == dealer, "Dealer cannot place bets.");
        require(phase == Phase.PlaceBets, "Not taking any new players.");
        require(msg.value == initialBet, "Incorrect initial bet.");
        players.push(msg.sender);

        playerDecisions[msg.sender] = PlayerDecision.Undecided;
    }

    function deal() public {
        require(msg.sender == dealer, "Only the dealer can deal");
        require(
            block.timestamp >= currentRoundTimeout,
            "Current round is still running."
        );

        require(
            phase == Phase.PlaceBets || phase == Phase.HitOrStand,
            "Game not in correct state."
        );

        if (phase == Phase.PlaceBets) {
            dealInitialHand();
            dealCardToDealer();
            phase = Phase.HitOrStand;
        } else if (phase == Phase.HitOrStand) {
            dealCardsToPlayers();
            finalDealerReveal();
        }

        currentRoundTimeout = block.timestamp + roundSessionExpiry;
    }

    function getCard() private view returns (Card card) {
        return Card(getRandomNumber() % NUMBER_OF_CARDS);
    }

    function getRandomNumber() internal view returns (uint256) {
        return
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
    }

    function dealCardsToPlayers() private {
        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            PlayerDecision decision = playerDecisions[playerAddress];
            if (decision == PlayerDecision.Hit) {
                hands[playerAddress].push(getCard());
                if (sumOfHand(hands[playerAddress]) > BLACK_JACK) {
                    // sum of player cards is higher than BLACK_JACK
                    emit Bust(playerAddress);
                    playerDecisions[playerAddress] = PlayerDecision.Stand;
                } else {
                    playerDecisions[playerAddress] = PlayerDecision.Undecided;
                }
            } else if (decision == PlayerDecision.Undecided) {
                // handle the case the player missed the opportunity to decide on hit or stand
                emit Stand(playerAddress);
                playerDecisions[playerAddress] = PlayerDecision.Stand;
            }
        }
    }

    function dealInitialHand() private {
        for (uint256 i = 0; i < players.length; i++) {
            address playerAddress = players[i];
            hands[playerAddress].push(getCard());
            hands[playerAddress].push(getCard());
        }
    }

    function dealCardToDealer() private {
        hands[dealer].push(getCard());
    }

    function finalDealerReveal() private {
        while (sumOfHand(hands[dealer]) < DEALER_DECISION) {
            hands[dealer].push(getCard());
        }
        if (sumOfHand(hands[dealer]) > BLACK_JACK) {
            emit Bust(dealer);
        }
    }

    function hit() public {
        require(
            playerDecisions[msg.sender] != PlayerDecision.Stand,
            "Player already selected stand once."
        );
        decide(PlayerDecision.Hit);
        emit Hit(msg.sender);
    }

    function stand() public {
        require(
            playerDecisions[msg.sender] != PlayerDecision.Hit,
            "Player already selected hit once."
        );
        decide(PlayerDecision.Stand);
        emit Stand(msg.sender);
    }

    function decide(PlayerDecision decision) private {
        require(
            playerDecisions[msg.sender] != 0,
            "Player didn't place any bets."
        );
        require(
            phase == Phase.HitOrStand,
            "Currently not allowing hit or stand actions."
        );
        require(
            block.timestamp <= currentRoundTimeout,
            "Round does not accept any more changes"
        );

        playerDecisions[msg.sender] = decision;
    }

    function sumOfHand(
        Card[] memory hand
    ) private pure returns (uint256 totalSum) {
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
        HitOrStand
    }

    enum PlayerDecision {
        Undecided,
        Hit,
        Stand
    }
}
