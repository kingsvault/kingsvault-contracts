// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

// Original file @chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol
abstract contract VRFConsumerBaseV2 is Initializable, OwnableUpgradeable {
    struct VrfStorage {
        address _vrfCoordinator;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.vrf")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VrfStorageLocation =
        0x2168c89e472257df265406ae281e71a9a09e0b3846f5d33f67a174b58c0b4d00;

    function _getVrfStorage() private pure returns (VrfStorage storage $) {
        assembly {
            $.slot := VrfStorageLocation
        }
    }

    error OnlyCoordinatorCanFulfill(address have, address want);

    /**
     * @param vrfCoordinator_ address of VRFCoordinator contract
     */
    function __VRFConsumerBaseV2_init(
        address vrfCoordinator_
    ) internal onlyInitializing {
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);
    }

    /**
     * @param vrfCoordinator_ address of VRFCoordinator contract
     */
    function __VRFConsumerBaseV2_init_unchained(
        address vrfCoordinator_
    ) internal onlyInitializing {
        VrfStorage storage $ = _getVrfStorage();
        $._vrfCoordinator = vrfCoordinator_;
    }

    function vrfCoordinator() public pure returns (address) {
        VrfStorage memory $ = _getVrfStorage();
        return $._vrfCoordinator;
    }

    function setVrfCoordinator(address vrfCoordinator_) external onlyOwner {
        VrfStorage storage $ = _getVrfStorage();
        $._vrfCoordinator = vrfCoordinator_;
    }

    /**
     * @notice fulfillRandomness handles the VRF response. Your contract must
     * @notice implement it. See "SECURITY CONSIDERATIONS" above for important
     * @notice principles to keep in mind when implementing your fulfillRandomness
     * @notice method.
     *
     * @dev VRFConsumerBaseV2 expects its subcontracts to have a method with this
     * @dev signature, and will call it once it has verified the proof
     * @dev associated with the randomness. (It is triggered via a call to
     * @dev rawFulfillRandomness, below.)
     *
     * @param requestId The Id initially returned by requestRandomness
     * @param randomWords the VRF output expanded to the requested number of words
     */
    // solhint-disable-next-line chainlink-solidity/prefix-internal-functions-with-underscore
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual;

    // rawFulfillRandomness is called by VRFCoordinator when it receives a valid VRF
    // proof. rawFulfillRandomness then calls fulfillRandomness, after validating
    // the origin of the call
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        address sender = _msgSender();
        address _vrfCoordinator = vrfCoordinator();
        if (sender != _vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(sender, _vrfCoordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }
}
