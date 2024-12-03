// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TODO
/// @author TODO
/// @notice TODO
contract BlockJack {
    uint16 public initialBet;
    uint16 public roundSessionExpiry;
    address public dealer;
    uint256 currentRoundTimeout;
    uint256 multiplier;
    uint8 numberOfCards;

    event Hit(address indexed player);
    event Stand(address indexed player);
    event Bust(address indexed player);

    address[] players;
    mapping(address => Card[]) public hand;
    mapping(address => uint256) public bets;
    mapping(address => PlayerDecision) public playerDecision;
    Phase public phase;

    constructor(
        uint16 _initialBet,
        uint16 _roundSessionExpiry,
        uint256 _multiplier
    ) {
        dealer = msg.sender;
        initialBet = _initialBet;
        roundSessionExpiry = _roundSessionExpiry;
        phase = Phase.PlaceBets;
        multiplier = _multiplier;
        numberOfCards = setNumberOfCards();
    }

    function placeBet() public payable {
        require(phase == Phase.PlaceBets, "Not taking any new players.");
        require(msg.value == initialBet, "Incorrect initial bet.");
        bets[msg.sender] = msg.value;
        players.push(msg.sender);

        playerDecision[msg.sender] = PlayerDecision.Undecided;
    }

    function deal(uint256 injectedRandomness) public {
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
            dealCardsToPlayer(2);
            dealCardsToDealer();
            phase = Phase.HitOrStand;
        } else if (phase == Phase.HitOrStand) {
            dealCardsToPlayer(1);
            finalDealerReveal();
        }

        currentRoundTimeout = block.timestamp + roundSessionExpiry;
    }

    function setNumberOfCards() public view returns (uint8) {
        uint8 numberOfCards = 0;
        while(Card(numberOfCards) == Card.King) {
            numberOfCards++;
        }
        return numberOfCards;
    }

    function getCard(uint256 injectedRandomness) private returns (Card card) {
        return Card(injectedRandomness % numberOfCards);
    }

    function dealCardsToPlayer(uint8 cards) private {
        for (uint i = 0; i < players.length; i++) {
            address playerAddress= players[i];
            if(playerDecision[playerAddress] != PlayerDecision.Stand){
                for (uint j = 0; i < cards; j++) {
                    hand[playerAddress].push(getCard());
                }
                playerDecision[playerAddress] = PlayerDecision.Undecided;
            }
        }
    }

    function dealCardsToDealer() private {
        //todo give one to dealer
    }

    function finalDealerReveal() private {
        //todo give one to dealer
    }

    function hit() public {
        require(
            playerDecision[msg.sender] != PlayerDecision.Stand,
            "Player already selected stand once."
        );
        decide(PlayerDecision.Hit);
        emit Hit(msg.sender);
    }

    function stand() public {
        require(
            playerDecision[msg.sender] != PlayerDecision.Hit,
            "Player already selected hit once."
        );
        decide(PlayerDecision.Stand);
        emit Stand(msg.sender);
    }

    function decide(PlayerDecision decision) private {
        require(bets[msg.sender] != 0, "Player didn't place any bets.");
        require(
            phase == Phase.HitOrStand,
            "Currently not allowing hit or stand actions."
        );
        require(
            block.timestamp <= currentRoundTimeout,
            "Round does not accept any more changes"
        );

        playerDecision[msg.sender] = decision;
        emit Hit(msg.sender);
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
}
