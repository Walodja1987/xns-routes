// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry.
interface IXNSRoutes {
    error ZeroAddress();
    error InvalidXnsName();
    error InvalidRoutePrefix();
    error InvalidRoute();
    error InvalidTarget();
    error NotXnsNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error RouteBookFrozen();
    error RouteAlreadyExists();
    error CannotDeleteFrozenRoute();

    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
    }

    event RouteCreated(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    event RouteUpdated(
        string xnsName,
        string routePrefix,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    event RouteActiveStatusUpdated(string xnsName, string routePrefix, string route, bool isActive);

    event RouteFrozen(string xnsName, string routePrefix, string route);

    event RouteBookFrozenForName(string xnsName);

    event RouteDeleted(string xnsName, string routePrefix, string route);

    function XNS() external view returns (address);

    function routeBookFrozen(bytes32 xnsNameKey) external view returns (bool);

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

    function activateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external;

    function deactivateRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external;

    function deleteRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external;

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

    function freezeRoute(string calldata xnsName, string calldata routePrefix, string calldata route) external;

    function freezeRouteBook(string calldata xnsName) external;

    function getRouteInfo(string calldata xnsName, string calldata routePrefix, string calldata route)
        external
        view
        returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExists(string calldata xnsName, string calldata routePrefix, string calldata route)
        external
        view
        returns (bool);
}
