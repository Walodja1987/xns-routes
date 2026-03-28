// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry.
interface IXNSRoutes {
    error ZeroAddress();
    error InvalidXnsName();
    error InvalidChain();
    error InvalidRoute();
    error InvalidTarget();
    error NotXnsNameOwner();
    error RouteNotFound();
    error CannotUpdateFrozenRoute();
    error RouteBookFrozen();

    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
    }

    event RouteSet(
        string indexed xnsName,
        string indexed chain,
        string route,
        address indexed target,
        bool isActive,
        bool isFrozen,
        uint32 routeType
    );

    event RouteActivationSet(
        string indexed xnsName,
        string indexed chain,
        string route,
        bool isActive
    );

    event RouteFrozen(string indexed xnsName, string indexed chain, string route);

    event RouteBookFrozenForName(string indexed xnsName);

    function XNS() external view returns (address);

    function routeBookFrozen(bytes32 xnsNameKey) external view returns (bool);

    function setRoute(
        string calldata xnsName,
        string calldata chain,
        string calldata route,
        address target,
        uint32 routeType,
        bool isActive,
        bool freezeImmediately
    ) external;

    function setRouteActive(
        string calldata xnsName,
        string calldata chain,
        string calldata route,
        bool isActive
    ) external;

    function freezeRoute(string calldata xnsName, string calldata chain, string calldata route) external;

    function freezeRoutes(string calldata xnsName) external;

    function getRoute(string calldata xnsName, string calldata chain, string calldata route)
        external
        view
        returns (address target);

    function getRouteInfo(string calldata xnsName, string calldata chain, string calldata route)
        external
        view
        returns (address target, bool isActive, bool isFrozen, uint32 routeType);

    function routeExists(string calldata xnsName, string calldata chain, string calldata route)
        external
        view
        returns (bool);
}
