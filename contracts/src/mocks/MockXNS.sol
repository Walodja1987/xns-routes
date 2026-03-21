// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Test double for XNS: configurable name → owner resolution and per-label validity.
contract MockXNS {
    mapping(bytes32 => address) private _resolver;
    mapping(bytes32 => bool) private _labelInvalid;

    function setResolution(string calldata fullName, address addr) external {
        _resolver[keccak256(bytes(fullName))] = addr;
    }

    function getAddress(string calldata fullName) external view returns (address addr) {
        return _resolver[keccak256(bytes(fullName))];
    }

    function setLabelInvalid(string calldata labelOrNamespace, bool invalid) external {
        _labelInvalid[keccak256(bytes(labelOrNamespace))] = invalid;
    }

    function isValidLabelOrNamespace(string calldata labelOrNamespace) external view returns (bool isValid) {
        return !_labelInvalid[keccak256(bytes(labelOrNamespace))];
    }
}
