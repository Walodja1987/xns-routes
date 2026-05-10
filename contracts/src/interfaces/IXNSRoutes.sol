// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry. Dotless `xnsName` arguments are
///         normalized to `label.x` for auth, storage keys, views, and event strings.
interface IXNSRoutes {
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
    }

    event RouteCreated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    event RouteTargetUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        address indexed newTarget
    );

    event RouteTypeUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        uint32 newRouteType
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route,
        bool isActive
    );

    event RouteFrozen(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route
    );

    event RouteBookFrozenForName(bytes32 indexed nameHash, string xnsName);

    event RouteDeleted(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routePrefix,
        string route
    );

    function XNS() external view returns (address);

    function isRouteBookFrozen(string calldata xnsName) external view returns (bool);

    function createRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external;

    function updateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external;

    function activateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external;

    function deactivateRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external;

    function deleteRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external;

    function updateTarget(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        address newTarget
    ) external;

    function updateRouteType(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route,
        uint32 newRouteType
    ) external;

    function freezeRoute(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external;

    function freezeRouteBook(string calldata xnsName) external;

    function getRouteInfo(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExists(
        string calldata xnsName,
        string calldata routePrefix,
        string calldata route
    ) external view returns (bool);

    function getRouteInfoFromPath(
        string calldata fullRoutePath
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExistsFromPath(string calldata fullRoutePath) external view returns (bool exists);

    function splitFullPath(
        string calldata fullRoutePath
    ) external pure returns (string memory xnsName, string memory routePrefix, string memory route);

    function isValidRoutePrefix(string calldata routePrefix) external pure returns (bool valid);

    function isValidRoute(string calldata route) external pure returns (bool valid);

    function isValidRoutePrefixAndRoute(
        string calldata routePrefix,
        string calldata route
    ) external pure returns (bool valid);

    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count);

    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys);

    function getRouteRecordByRouteKey(
        bytes32 routeKey
    ) external view returns (RouteRecord memory record);

    function getRouteRecordByRouteKey(
        bytes32[] calldata routeKeys
    ) external view returns (RouteRecord[] memory records);
}
