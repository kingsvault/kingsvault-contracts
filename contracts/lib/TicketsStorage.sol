// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

library TicketsStorage {
    struct Layout {
        // =============================================================
        //                            STORAGE
        // =============================================================

        // The next ticket ID to be minted.
        uint256 _currentIndex;
        // Mapping from ticket ID to ownership details
        // An empty struct value does not necessarily mean the ticket is unowned.
        // See {_packedOwnershipOf} implementation for details.
        //
        // Bits Layout:
        // - [0..159]   `addr`
        // - [160..223] `startTimestamp`
        // - [224]      `burned`
        // - [225]      `nextInitialized`
        // - [232..255] `extraData`
        mapping(uint256 => uint256) _packedOwnerships;
        // Mapping owner address to address data.
        //
        // Bits Layout:
        // - [0..63]    `balance`
        // - [64..127]  `numberMinted`
        // - [128..191] `numberBurned`
        // - [192..255] `aux`
        mapping(address => uint256) _packedAddressData;
        // The amount of tickets minted above `_ticketSequentialUpTo()`.
        // We call these spot mints (i.e. non-sequential mints).
        uint256 _spotMinted;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.Tickets")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant STORAGE_SLOT =
        0xe4d3b7f8a8cf6ee3d811516e71f399987a0e9cce9f21ebbe6298a85ee76e5600;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
