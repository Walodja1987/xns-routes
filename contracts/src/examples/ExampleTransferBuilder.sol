// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

struct ParamSpec {
    string name;
    string paramType;
}

interface IXNSRouteBuilderV1 {
    function suggestedRouteName() external pure returns (string memory);
    function title() external pure returns (string memory);
    function getParamSpecs() external pure returns (ParamSpec[] memory specs);
}

contract ExampleTransferBuilder is IXNSRouteBuilderV1 {
    function suggestedRouteName() external pure returns (string memory) {
        return "transfer";
    }

    function title() external pure returns (string memory) {
        return "Example ETH Transfer";
    }

    function getParamSpecs() external pure returns (ParamSpec[] memory specs) {
        specs = new ParamSpec;
        specs[0] = ParamSpec({name: "to", paramType: "address"});
        specs[1] = ParamSpec({name: "amount", paramType: "uint256"});
    }

    function build(
        address to,
        uint256 amount
    )
        external
        pure
        returns (
            uint256 targetChainId,
            address target,
            uint256 value,
            bytes memory data
        )
    {
        targetChainId = 1;
        target = to;
        value = amount;
        data = "";
    }
}