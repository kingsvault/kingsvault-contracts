// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {LinkTokenInterface} from "../interfaces/LinkTokenInterface.sol";

/**
 * @title VRFConsumerBaseV2
 * @dev Abstract contract for integrating Chainlink VRF (Verifiable Random Function) in upgradeable contracts.
 * Inherits from Initializable and OwnableUpgradeable.
 * Original file chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol
 * https://docs.chain.link/vrf/v2/subscription/examples/programmatic-subscription
 */
abstract contract VRFConsumerBaseV2 is Initializable, OwnableUpgradeable {
    /// @dev Error thrown when a non-coordinator address attempts to fulfill randomness.
    error OnlyCoordinatorCanFulfill(address have, address want);

    struct VrfStorage {
        uint64 _subscriptionId;
        address _vrfCoordinator; // Address of the Chainlink VRF Coordinator contract
        address _linkToken; // Address of the Chainlink Token contract
    }

    /**
     * @dev Retrieves the storage struct for VRF configuration using assembly.
     */
    function _getVrfStorage() private pure returns (VrfStorage storage $) {
        // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.vrf")) - 1)) & ~bytes32(uint256(0xff))
        assembly {
            $.slot := 0x2168c89e472257df265406ae281e71a9a09e0b3846f5d33f67a174b58c0b4d00
        }
    }

    /**
     * @dev Initializes the VRFConsumerBaseV2 contract.
     * @param vrfCoordinator_ Address of the Chainlink VRF Coordinator.
     * @param linkToken_ Address of the Chainlink Token contract.
     */
    function __VRFConsumerBaseV2_init(
        address vrfCoordinator_,
        address linkToken_
    ) internal onlyInitializing {
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_, linkToken_);
    }

    /**
     * @dev Initializes the VRF coordinator address.
     * @param vrfCoordinator_ Address of the Chainlink VRF Coordinator.
     * @param linkToken_ Address of the Chainlink Token contract.
     */
    function __VRFConsumerBaseV2_init_unchained(
        address vrfCoordinator_,
        address linkToken_
    ) internal onlyInitializing {
        _getVrfStorage()._vrfCoordinator = vrfCoordinator_;
        _getVrfStorage()._linkToken = linkToken_;

        _vrfCreateNewSubscription();
    }

    function _vrfSubscriptionId() internal view returns (uint64) {
        return _getVrfStorage()._subscriptionId;
    }

    /**
     * @dev Returns the address of the VRF Coordinator.
     */
    function _vrfCoordinatorAddress() internal view returns (address) {
        return _getVrfStorage()._vrfCoordinator;
    }

    /**
     * @dev Returns the Interface of the VRF Coordinator.
     */
    function _vrfCoordinator()
        internal
        view
        returns (VRFCoordinatorV2Interface)
    {
        return VRFCoordinatorV2Interface(_vrfCoordinatorAddress());
    }

    function _getLinkToken() internal view returns (LinkTokenInterface) {
        return LinkTokenInterface(_getVrfStorage()._linkToken);
    }

    // TODO remove. only for testnet
    function rawFulfillRandomWordsTest(
        uint256 requestId,
        uint256[] memory randomWords
    ) external onlyOwner {
        _fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Called by the Chainlink VRF Coordinator to provide randomness.
     * Ensures that only the correct VRF Coordinator can call it.
     * @param requestId The unique identifier for the randomness request.
     * @param randomWords The array of random words provided by Chainlink VRF.
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        address sender = _msgSender();
        address vrfCoordinator = _vrfCoordinatorAddress();
        if (sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(sender, vrfCoordinator);
        }
        _fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @notice This function should be implemented in derived contracts to handle VRF responses.
     * @param requestId The unique identifier for the randomness request.
     * @param randomWords The array of random words provided by Chainlink VRF.
     */
    function _fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual;

    // Create a new subscription when the contract is initially deployed.
    function _vrfCreateNewSubscription() private {
        VRFCoordinatorV2Interface coordinator = _vrfCoordinator();
        uint64 subscriptionId = coordinator.createSubscription();
        _getVrfStorage()._subscriptionId = subscriptionId;

        // Add this contract as a consumer of its own subscription.
        coordinator.addConsumer(subscriptionId, address(this));
    }

    // Assumes this contract owns link.
    // 1000000000000000000 = 1 LINK
    function vrfTopUpSubscription(uint256 amount) external onlyOwner {
        _getLinkToken().transferAndCall(
            _vrfCoordinatorAddress(),
            amount,
            abi.encode(_vrfSubscriptionId())
        );
    }

    function vrfAddConsumer(address consumerAddress) external onlyOwner {
        // Add a consumer contract to the subscription.
        _vrfCoordinator().addConsumer(_vrfSubscriptionId(), consumerAddress);
    }

    function vrfRemoveConsumer(address consumerAddress) external onlyOwner {
        // Remove a consumer contract from the subscription.
        _vrfCoordinator().removeConsumer(_vrfSubscriptionId(), consumerAddress);
    }

    function vrfCancelSubscription(address receivingWallet) external onlyOwner {
        // Cancel the subscription and send the remaining LINK to a wallet address.
        _vrfCoordinator().cancelSubscription(
            _vrfSubscriptionId(),
            receivingWallet
        );
        _getVrfStorage()._subscriptionId = 0;
    }

    // Transfer this contract's funds to an address.
    // 1000000000000000000 = 1 LINK
    function vrfWithdrawLinkTo(address to, uint256 amount) external onlyOwner {
        _getLinkToken().transfer(to, amount);
    }
}
