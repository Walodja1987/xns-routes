// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry. Dotless `xnsName` arguments are
///         normalized to `label.x` for auth, storage keys, and views. Events emit the
///         canonical form as `canonicalXNSName`.
interface IXNSRoutes {
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        address activeController;
    }

    event RouteCreated(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        address indexed target,
        uint32 routeType,
        bool isActive,
        address activeController
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameHash,
        bytes32 indexed routeKey,
        string canonicalXNSName,
        string routeScope,
        string routeLabel,
        bool isActive
    );

    event RouteBookFrozen(bytes32 indexed xnsNameHash, string canonicalXNSName);

    function XNS() external view returns (address);

    function isRouteBookFrozen(string calldata xnsName) external view returns (bool);

    function createRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType
    ) external;

    function createRouteWithController(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool isActive,
        address activeController
    ) external;

    function activateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external;

    function deactivateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external;

    function freezeRouteBook(string calldata xnsName) external;

    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record);

    function getRouteRecord(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record);

    function getRouteRecord(string calldata registryXRL) external view returns (RouteRecord memory record);

    function resolveRouteIfActive(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType);

    function resolveRouteIfActive(
        string calldata registryXRL
    ) external view returns (address target, uint32 routeType);

    function resolveRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType);

    function resolveRoute(
        string calldata registryXRL
    ) external view returns (address target, uint32 routeType);

    function splitRegistryXRL(
        string calldata registryXRL
    ) external pure returns (string memory xnsName, string memory routeScope, string memory routeLabel);

    function isValidRouteScope(string calldata routeScope) external pure returns (bool valid);

    function isValidRouteLabel(string calldata routeLabel) external pure returns (bool valid);

    function isValidRouteScopeAndLabel(
        string calldata routeScope,
        string calldata routeLabel
    ) external pure returns (bool valid);

    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count);

    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys);
}
