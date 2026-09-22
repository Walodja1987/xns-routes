// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Test double for XNSv2: configurable `label AT namespace` → owner resolution.
contract MockXNS {
    mapping(bytes32 => address) private _resolver;

    function setResolution(
        string calldata label,
        string calldata namespace,
        address addr
    ) external {
        _resolver[_nameKey(label, namespace)] = addr;
    }

    function getAddress(
        string calldata label,
        string calldata namespace
    ) external view returns (address addr) {
        return _resolver[_nameKey(label, namespace)];
    }

    function getAddress(string calldata fullName) external view returns (address addr) {
        return _resolver[keccak256(bytes(fullName))];
    }

    function registerName(string calldata label, string calldata namespace) external payable {
        _resolver[_nameKey(label, namespace)] = msg.sender;
    }

    function getNamespacePrice(string calldata) external pure returns (uint256) {
        return 0;
    }

    function _nameKey(
        string memory label,
        string memory namespace
    ) private pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(label, "@", namespace));
    }
}
