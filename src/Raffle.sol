// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// To debug directly on contract - Remember to remove before deploy!!
import {console} from "forge-std/Test.sol";

/**
 * @title A sampleRaffle Contract
 * @author Przemo
 * @notice Create a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    /** Type Errors */
    error Raffle__NotEnoughtEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        RaffleState raffleState
    );

    /** Type declaration */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    uint16 private constant REQ_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /** Type VRF params */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint256 private immutable i_interval; // @dev Duration of the lottery in seconds
    uint256 private immutable i_enterenceFee; // Min amount of ETH to call contract
    bytes32 private immutable i_gasLane; // Hash to oracle job to crate the VRF proof
    uint64 private immutable i_subId; // ID of the VRF sub - script will add this
    uint32 private immutable i_callbackGasLimit; // Max possible spend gas for receive

    address payable[] private s_players; // List of joined players
    uint256 private s_lastTimeStamp; // When contract was created on blockchain
    address private s_winner; // Random winner of the contract in future
    RaffleState s_raffleState = RaffleState.OPEN; // Init state of contract as open

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 enterenceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_enterenceFee = enterenceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subId = subId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_enterenceFee, "Not enough ETH sent!");
        if (msg.value < i_enterenceFee) {
            revert Raffle__NotEnoughtEthSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked ?
    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep.
     * The following should be true for this to return true
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implict) The subscrition is funded with LINK
     * @return upkeepNeed
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeed, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;

        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_players.length > 0;

        upkeepNeed = (timeHasPassed && isOpen && hasBalance && hasPlayer);
        return (upkeepNeed, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState
            );
        }

        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert();
        }

        s_raffleState = RaffleState.CALCULATING;

        // Will revert if subscription is not set and funded.
        // Make a request to chainlink note ->
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subId,
            REQ_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedRaffleWinner(requestId);
    }

    // -> Callback to catch response from chainlink note
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];

        s_winner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        (bool success, ) = winner.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }

        emit PickedWinner(winner);
    }

    /** Getter Function */
    function getEnteranceFee() external view returns (uint256) {
        return i_enterenceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getWinner() external view returns (address) {
        return s_winner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLasTimestamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
