// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Generic parameter schema entry for route builders.
/// Examples:
/// - { name: "to", paramType: "address" }
/// - { name: "amount", paramType: "uint256" }
/// - { name: "recipients", paramType: "address[]" }
/// - { name: "payment", paramType: "(address,uint256)" }
struct ParamSpec {
    string name;
    string paramType;
}

/// @notice Template interface for XNS route build contracts.
///
/// Conventions:
/// - function name is always `build`
/// - build parameter order must exactly match `getParamSpecs()`
/// - `paramType` uses canonical ABI type strings
/// - build returns a standard tx template
interface IXNSRouteBuilderV1 {
    /// @notice Suggested default route name for UI prefill.
    function suggestedRouteName() external pure returns (string memory);

    /// @notice Human-readable title for builder libraries.
    function title() external pure returns (string memory);

    /// @notice Returns the canonical schema for the build function inputs.
    ///
    /// Examples:
    /// [
    ///   { name: "to", paramType: "address" },
    ///   { name: "amount", paramType: "uint256" }
    /// ]
    ///
    /// [
    ///   { name: "payment", paramType: "(address,uint256)" },
    ///   { name: "memo", paramType: "string" }
    /// ]
    function getParamSpecs() external pure returns (ParamSpec[] memory specs);

    /// @notice Build a tx template.
    ///
    /// The parser/wallet:
    /// - reads `getParamSpecs()`
    /// - maps named route params into the canonical order
    /// - dynamically derives the typed `build(...)` signature
    /// - calls this function
    ///
    /// Must return:
    /// - targetChainId: the chain where the tx must be executed
    /// - target: the target contract / address
    /// - value: native token amount to send
    /// - data: calldata
    function build()
        external
        view
        returns (
            /* typed inputs, route-specific */ uint256 targetChainId,
            address target,
            uint256 value,
            bytes memory data
        );
}
