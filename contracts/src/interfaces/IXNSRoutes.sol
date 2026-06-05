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
        string routeScope,
        string routeLabel,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    event RouteTargetUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routeScope,
        string routeLabel,
        address previousTarget,
        address indexed newTarget
    );

    event RouteTypeUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routeScope,
        string routeLabel,
        uint32 previousRouteType,
        uint32 newRouteType
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routeScope,
        string routeLabel,
        bool isActive
    );

    /// Emitted when an existing route becomes frozen (`updateRoute` / `freezeRoute`). Initial freeze-at-create is only in `RouteCreated`.
    event RouteFrozen(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routeScope,
        string routeLabel
    );

    event RouteBookFrozenForName(bytes32 indexed nameHash, string xnsName);

    event RouteDeleted(
        bytes32 indexed nameHash,
        bytes32 indexed routeKey,
        string xnsName,
        string routeScope,
        string routeLabel
    );

    function XNS() external view returns (address);

    function isRouteBookFrozen(string calldata xnsName) external view returns (bool);

    function createRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
    ) external;

    function updateRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        bool activate,
        bool freeze
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

    function deleteRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external;

    function updateTarget(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        address newTarget
    ) external;

    function updateRouteType(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel,
        uint32 newRouteType
    ) external;

    function freezeRoute(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external;

    function freezeRouteBook(string calldata xnsName) external;

    function getRouteInfo(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExists(
        string calldata xnsName,
        string calldata routeScope,
        string calldata routeLabel
    ) external view returns (bool);

    function getRouteInfoFromXRL(
        string calldata xrl
    ) external view returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExistsFromXRL(string calldata xrl) external view returns (bool exists);

    function splitXRL(
        string calldata xrl
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

    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record);

    function getRouteRecords(
        bytes32[] calldata routeKeys
    ) external view returns (RouteRecord[] memory records);
}
