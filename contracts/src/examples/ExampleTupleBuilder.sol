// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IXNSRouteBuilderV1, ParamSpec} from "./IXNSRouteBuilderV1.sol";

contract ExampleTupleBuilder is IXNSRouteBuilderV1 {
    struct Payment {
        address to;
        uint256 amount;
    }

    function suggestedRouteName() external pure returns (string memory) {
        return "payment";
    }

    function title() external pure returns (string memory) {
        return "Example Payment";
    }

    function getParamSpecs() external pure returns (ParamSpec[] memory specs) {
        specs = new ParamSpec[](1);
        specs[0] = ParamSpec({name: "payment", paramType: "(address,uint256)"});
    }

    function build(
        Payment calldata payment
    )
        external
        pure
        returns (uint256 targetChainId, address target, uint256 value, bytes memory data)
    {
        targetChainId = 1;
        target = payment.to;
        value = payment.amount;
        data = "";
    }
}
