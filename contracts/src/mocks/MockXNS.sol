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

    /// @dev Mirrors XNS `isValidLabelOrNamespace` charset rules, then applies `setLabelInvalid` overrides for tests.
    function isValidLabelOrNamespace(
        string calldata labelOrNamespace
    ) external view returns (bool isValid) {
        if (!_isValidLabelOrNamespaceLikeXns(labelOrNamespace)) return false;
        return !_labelInvalid[keccak256(bytes(labelOrNamespace))];
    }

    /// @dev Same rules as XNS `_isValidLabelOrNamespace` (length, `a-z` / `0-9` / `-`, hyphen placement).
    function _isValidLabelOrNamespaceLikeXns(
        string calldata labelOrNamespace
    ) private pure returns (bool) {
        bytes memory b = bytes(labelOrNamespace);
        uint256 len = b.length;
        if (len == 0 || len > 20) return false;

        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            bool isLowercaseLetter = (c >= 0x61 && c <= 0x7A);
            bool isDigit = (c >= 0x30 && c <= 0x39);
            bool isHyphen = (c == 0x2D);
            if (!(isLowercaseLetter || isDigit || isHyphen)) return false;
            if (isHyphen && i > 0 && b[i - 1] == 0x2D) return false;
        }

        if (b[0] == 0x2D || b[len - 1] == 0x2D) return false;
        return true;
    }

    /// @dev Mirrors XNS name keying: `keccak256(abi.encodePacked(label, ".", namespace))`.
    function registerName(string calldata label, string calldata namespace) external payable {
        bytes32 key = keccak256(abi.encodePacked(label, ".", namespace));
        _resolver[key] = msg.sender;
    }
}
