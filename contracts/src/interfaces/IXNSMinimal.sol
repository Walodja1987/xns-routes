// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSMinimal
/// @notice Minimal XNS registry surface required by `XNSRoutes` (resolution, label rules, and `registerName` at deploy).
interface IXNSMinimal {
    function getAddress(string calldata fullName) external view returns (address addr);
    function registerName(string calldata label, string calldata namespace) external payable;
}
