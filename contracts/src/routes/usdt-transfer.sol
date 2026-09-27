// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IXNSRouteBuilderV1, ParamSpec} from "../interfaces/IXNSRouteBuilderV1.sol";

interface IXNSForBuilderNaming {
    function registerName(string calldata label, string calldata namespace) external payable;
    function isValidLabelOrNamespace(
        string calldata labelOrNamespace
    ) external pure returns (bool isValid);
}

/// @title USDTTransferEthBuilder
/// @notice Build contract for USDT transfers on Ethereum mainnet.
///
/// Example shared link:
///   usdt AT action/transfer-usdt?to=0x1234...&amount=100
///
/// Returns tx template for:
///   USDT.transfer(to, amountWhole * 1e6)
///
/// Optional constructor feature:
/// - the deployer may assign an XNS name to this build contract itself
/// - if `routeLabel` is empty, no name is assigned
/// - if `routeLabel` is non-empty, the constructor calls XNS.registerName(...)
///   from this contract, so the name is registered to the build contract address
contract USDTTransferEthBuilder is IXNSRouteBuilderV1 {
    error ZeroXNS();
    error ZeroToken();
    error ZeroRecipient();
    error InvalidAmount();
    error InvalidRouteLabel();
    error InvalidRouteNamespace();

    /// @notice Ethereum mainnet chain id
    uint256 public constant TARGET_CHAIN_ID = 1;

    /// @notice ERC20 transfer selector
    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    /// @notice XNS contract used only for optional self-naming in constructor
    address public immutable XNS;

    /// @notice USDT token contract on Ethereum
    address public immutable TOKEN;

    /// @notice USDT uses 6 decimals
    uint256 public constant SCALE = 1e6;

    constructor(
        address xns_,
        address token_,
        string memory routeLabel,
        string memory routeNamespace
    ) payable {
        if (xns_ == address(0)) revert ZeroXNS();
        if (token_ == address(0)) revert ZeroToken();

        XNS = xns_;
        TOKEN = token_;

        // Optional: register a name for this builder contract itself.
        // If routeLabel is empty, skip.
        if (bytes(routeLabel).length != 0) {
            if (!IXNSForBuilderNaming(xns_).isValidLabelOrNamespace(routeLabel)) {
                revert InvalidRouteLabel();
            }
            if (!IXNSForBuilderNaming(xns_).isValidLabelOrNamespace(routeNamespace)) {
                revert InvalidRouteNamespace();
            }

            IXNSForBuilderNaming(xns_).registerName{value: msg.value}(routeLabel, routeNamespace);
        }
    }

    /// @notice Suggested default route name for UI prefill.
    function suggestedRouteName() external pure returns (string memory) {
        return "transfer-usdt";
    }

    /// @notice Human-readable title for builder libraries.
    function title() external pure returns (string memory) {
        return "USDT Transfer on Ethereum";
    }

    /// @notice Returns the canonical schema for the `build` inputs.
    ///
    /// `amount` is a whole-number USDT amount (e.g. 100 means 100 USDT).
    function getParamSpecs() external pure returns (ParamSpec[] memory specs) {
        specs = new ParamSpec[](2);
        specs[0] = ParamSpec({name: "to", paramType: "address"});
        specs[1] = ParamSpec({name: "amount", paramType: "uint256"});
    }

    /// @notice Build tx template for USDT.transfer(to, amountWhole * 1e6)
    /// @param to Recipient address
    /// @param amountWhole Whole-number USDT amount, e.g. 100 means 100 USDT
    /// @return targetChainId Ethereum mainnet chain id
    /// @return target USDT token contract
    /// @return value Native ETH value to send (always 0 for ERC20 transfer)
    /// @return data Calldata for USDT.transfer(to, scaledAmount)
    function build(
        address to,
        uint256 amountWhole
    )
        external
        view
        returns (uint256 targetChainId, address target, uint256 value, bytes memory data)
    {
        if (to == address(0)) revert ZeroRecipient();
        if (amountWhole == 0) revert InvalidAmount();

        uint256 scaledAmount = amountWhole * SCALE;

        targetChainId = TARGET_CHAIN_ID;
        target = TOKEN;
        value = 0;
        data = abi.encodeWithSelector(TRANSFER_SELECTOR, to, scaledAmount);
    }
}
