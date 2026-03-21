// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IXNSForRegisterNameBuilder {
    function registerName(string calldata label, string calldata namespace) external payable;
    function getNamespacePrice(string calldata namespace) external view returns (uint256);
    function isValidLabelOrNamespace(string calldata labelOrNamespace) external pure returns (bool isValid);
}

/// @title XNSRegisterNameBuilder
/// @notice Build contract for the route path:
///         xns.action/eth:register-name/label=bro/namespace=og
///
/// It returns the tx template for calling:
///         XNS.registerName(label, namespace)
///
/// Optional constructor feature:
/// - the deployer may assign an XNS name to this build contract itself
/// - if `routeLabel` is empty, no name is assigned
/// - if `routeLabel` is non-empty, the constructor calls XNS.registerName(...)
///   from this contract, so the name is registered to the build contract address
contract XNSRegisterNameBuilder {
    error ZeroXNS();
    error InvalidLabel();
    error InvalidNamespace();
    error InvalidRouteLabel();
    error InvalidRouteNamespace();

    /// @notice Ethereum mainnet
    uint256 public constant TARGET_CHAIN_ID = 1;

    /// @notice Deployed XNS contract
    address public immutable XNS;

    /// @dev selector for registerName(string,string)
    bytes4 public constant REGISTER_NAME_SELECTOR =
        bytes4(keccak256("registerName(string,string)"));

    constructor(
        address xns_,
        string memory routeLabel,
        string memory routeNamespace
    ) payable {
        if (xns_ == address(0)) revert ZeroXNS();
        XNS = xns_;

        // Optional: register a name for this builder contract itself.
        // If routeLabel is empty, skip.
        if (bytes(routeLabel).length != 0) {
            if (!IXNSForRegisterNameBuilder(xns_).isValidLabelOrNamespace(routeLabel)) {
                revert InvalidRouteLabel();
            }
            if (!IXNSForRegisterNameBuilder(xns_).isValidLabelOrNamespace(routeNamespace)) {
                revert InvalidRouteNamespace();
            }

            IXNSForRegisterNameBuilder(xns_).registerName{value: msg.value}(routeLabel, routeNamespace);
        }
    }

    /// @notice Suggested default route name for UI prefill.
    function suggestedRouteName() external pure returns (string memory) {
        return "register-name";
    }

    /// @notice Human-readable title for builder libraries.
    function title() external pure returns (string memory) {
        return "XNS Register Name";
    }

    /// @notice Build the tx template for XNS.registerName(label, namespace).
    /// @param label The label part, e.g. "bro"
    /// @param namespace The namespace part, e.g. "og"
    /// @return targetChainId Ethereum mainnet chain id
    /// @return target XNS contract address
    /// @return value ETH required for the registration
    /// @return data Calldata for XNS.registerName(label, namespace)
    function build(
        string calldata label,
        string calldata namespace
    )
        external
        view
        returns (
            uint256 targetChainId,
            address target,
            uint256 value,
            bytes memory data
        )
    {
        if (!IXNSForRegisterNameBuilder(XNS).isValidLabelOrNamespace(label)) {
            revert InvalidLabel();
        }
        if (!IXNSForRegisterNameBuilder(XNS).isValidLabelOrNamespace(namespace)) {
            revert InvalidNamespace();
        }

        targetChainId = TARGET_CHAIN_ID;
        target = XNS;
        value = IXNSForRegisterNameBuilder(XNS).getNamespacePrice(namespace);
        data = abi.encodeWithSelector(REGISTER_NAME_SELECTOR, label, namespace);
    }
}