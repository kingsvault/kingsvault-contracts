// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

abstract contract Metadata is
    Initializable,
    ERC1155Upgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable
{
    using Strings for uint256;

    struct MetadataStorage {
        string _name;
        string _symbol;
        string _baseURI;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MetadataStorageLocation =
        0xcc940b55fd63d6ffbe37b3e06982f371d55299a99d110340df096abb3f7ed400;

    function _getMetadataStorage()
        private
        pure
        returns (MetadataStorage storage $)
    {
        assembly {
            $.slot := MetadataStorageLocation
        }
    }

    /// @dev Emitted when the contract URI is updated.
    event ContractURIUpdated(string prevURI, string newURI);

    function __Metadata_init(
        string memory uri_,
        string memory name_,
        string memory symbol_,
        address royaltyReceiver_,
        uint96 royaltyFee_
    ) internal onlyInitializing {
        __Metadata_init_unchained(
            uri_,
            name_,
            symbol_,
            royaltyReceiver_,
            royaltyFee_
        );
    }

    function __Metadata_init_unchained(
        string memory uri_,
        string memory name_,
        string memory symbol_,
        address royaltyReceiver_,
        uint96 royaltyFee_
    ) internal onlyInitializing {
        MetadataStorage storage $ = _getMetadataStorage();
        $._name = name_;
        $._symbol = symbol_;
        $._baseURI = uri_;

        _setDefaultRoyalty(royaltyReceiver_, royaltyFee_);
    }

    /**
     * @dev Returns the proxy version, admin, and implementation addresses.
     * This function reads from the storage slots defined by the ERC1967 standard.
     * @return initializedVersion The initialized version of the contract.
     * @return admin The address of the admin.
     * @return implementation The address of the implementation contract.
     */
    function proxy()
        external
        view
        returns (
            uint64 initializedVersion,
            address admin,
            address implementation
        )
    {
        // @openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return (
            _getInitializedVersion(),
            StorageSlot.getAddressSlot(ADMIN_SLOT).value,
            StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value
        );
    }

    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._name;
    }

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._symbol;
    }

    function baseURI() external view returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._baseURI;
    }

    function setBaseURI(string memory newuri) external onlyOwner {
        string memory prev = contractURI();
        MetadataStorage storage $ = _getMetadataStorage();
        $._baseURI = newuri;
        emit ContractURIUpdated(prev, contractURI());
    }

    function contractURI() public pure returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return
            bytes($._baseURI).length > 0
                ? string.concat($._baseURI, "contract.json")
                : "";
    }

    function uri(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return
            bytes($._baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        $._baseURI,
                        Strings.toString(tokenId),
                        ".json"
                    )
                )
                : "";
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
}
