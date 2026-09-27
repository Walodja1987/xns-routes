// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IXNSRouteBuilderV1, ParamSpec} from "../interfaces/IXNSRouteBuilderV1.sol";

contract ExampleTransferBuilder is IXNSRouteBuilderV1 {
    function suggestedRouteName() external pure returns (string memory) {
        return "transfer";
    }

    function title() external pure returns (string memory) {
        return "Example ETH Transfer";
    }

    function getParamSpecs() external pure returns (ParamSpec[] memory specs) {
        specs = new ParamSpec[](2);
        specs[0] = ParamSpec({name: "to", paramType: "address"});
        specs[1] = ParamSpec({name: "amount", paramType: "uint256"});
    }

    function build(
        address to,
        uint256 amount
    )
        external
        pure
        returns (uint256 targetChainId, address target, uint256 value, bytes memory data)
    {
        targetChainId = 1;
        target = to;
        value = amount;
        data = "";
    }
}
