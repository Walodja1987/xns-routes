// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry.
interface IXNSRoutes {
    error ZeroXNS();
    error InvalidBaseName();
    error InvalidRoute();
    error InvalidTarget();
    error NotBaseNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error BaseRoutesFrozen();

    struct RouteRecord {
        address target;
        bool isActive;
        bool isFrozen;
        bool exists;
    }

    event RouteSet(
        string indexed baseName,
        string indexed route,
        address indexed target,
        bool isActive,
        bool isFrozen
    );

    event RouteActivationSet(string indexed baseName, string indexed route, bool isActive);

    event RouteFrozen(string indexed baseName, string indexed route);

    event BaseRoutesFrozenForName(string indexed baseName);

    function XNS() external view returns (address);

    function baseRoutesFrozen(bytes32 baseKey) external view returns (bool);

    function setRoute(
        string calldata baseName,
        string calldata route,
        address target,
        bool isActive,
        bool freezeImmediately
    ) external;

    function setRouteActive(string calldata baseName, string calldata route, bool isActive) external;

    function freezeRoute(string calldata baseName, string calldata route) external;

    function freezeRoutes(string calldata baseName) external;

    function getRoute(string calldata baseName, string calldata route) external view returns (address target);

    function getRouteInfo(string calldata baseName, string calldata route)
        external
        view
        returns (address target, bool isActive, bool isFrozen);

    function routeExists(string calldata baseName, string calldata route) external view returns (bool);
}
