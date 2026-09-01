// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSMinimal
/// @notice Minimal XNSv2 registry surface required by `XNSRoutes`.
interface IXNSMinimal {
    function getAddress(string calldata label, string calldata namespace) external view returns (address addr);

    function getAddress(string calldata fullName) external view returns (address addr);

    function registerName(string calldata label, string calldata namespace) external payable;

    function getNamespacePrice(string calldata namespace) external view returns (uint256 pricePerName);
}
