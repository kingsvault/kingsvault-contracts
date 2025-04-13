// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title VRFConsumerBaseV2
 * @dev Abstract contract for integrating Chainlink VRF (Verifiable Random Function) in upgradeable contracts.
 * Inherits from Initializable and OwnableUpgradeable.
 * Original file chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol
 */
abstract contract VRFConsumerBaseV2 is Initializable, OwnableUpgradeable {
    /// @dev Error thrown when a non-coordinator address attempts to fulfill randomness.
    error OnlyCoordinatorCanFulfill(address have, address want);

    struct VrfStorage {
        address _vrfCoordinator; // Address of the Chainlink VRF Coordinator contract
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
     */
    function __VRFConsumerBaseV2_init(
        address vrfCoordinator_
    ) internal onlyInitializing {
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);
    }

    /**
     * @dev Initializes the VRF coordinator address.
     * @param vrfCoordinator_ Address of the Chainlink VRF Coordinator.
     */
    function __VRFConsumerBaseV2_init_unchained(
        address vrfCoordinator_
    ) internal onlyInitializing {
        _getVrfStorage()._vrfCoordinator = vrfCoordinator_;
    }

    /**
     * @dev Returns the address of the VRF Coordinator.
     */
    function getVrfCoordinator() public view returns (address) {
        return _getVrfStorage()._vrfCoordinator;
    }

    /**
     * @dev Allows the owner to update the VRF Coordinator address.
     * @param vrfCoordinator_ New address of the VRF Coordinator.
     */
    function setVrfCoordinator(address vrfCoordinator_) external onlyOwner {
        _getVrfStorage()._vrfCoordinator = vrfCoordinator_;
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
        address vrfCoordinator = getVrfCoordinator();
        if (sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(sender, vrfCoordinator);
        }
        _fulfillRandomWords(requestId, randomWords);
    }
}
