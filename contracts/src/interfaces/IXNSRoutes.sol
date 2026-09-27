// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry (XNSv2 `label AT namespace/route` format).
interface IXNSRoutes {
    struct RouteRecord {
        bytes target;
        uint32 routeType;
        bool isActive;
        bool isFrozen;
        string routeLabel;
    }

    struct RouteEntry {
        bytes32 routeKey;
        RouteRecord record;
    }

    event RouteCreated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        bytes32 indexed targetHash,
        string label,
        string namespace,
        string routeLabel,
        uint32 routeType
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bool isActive
    );

    event RouteUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        bytes32 indexed targetHash,
        string label,
        string namespace,
        string routeLabel,
        uint32 routeType
    );

    event RouteFrozen(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel
    );

    event RouteBookClosed(bytes32 indexed xnsNameKey, string label, string namespace);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function XNS() external view returns (address);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function transferOwnership(address newOwner) external;

    function acceptOwnership() external;

    function renounceOwnership() external;

    function createRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType
    ) external;

    function activateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function deactivateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function updateRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        bytes calldata newTarget,
        uint32 newRouteType
    ) external;

    function freezeRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function batchFreezeRoutes(
        string calldata label,
        string calldata namespace,
        string[] calldata routeLabels
    ) external;

    function closeRouteBook(string calldata label, string calldata namespace) external;

    function closeRouteBook(string calldata xnsName) external;

    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record);

    function getRouteRecord(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record);

    function getRouteRecord(
        string calldata route
    ) external view returns (RouteRecord memory record);

    function getXNSNameKey(
        string calldata label,
        string calldata namespace
    ) external pure returns (bytes32 xnsNameKey);

    function getXNSNameKey(string calldata xnsName) external pure returns (bytes32 xnsNameKey);

    function getRouteKey(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external pure returns (bytes32 routeKey);

    function getRouteKey(string calldata route) external pure returns (bytes32 routeKey);

    function resolveRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (bytes memory target, uint32 routeType);

    function resolveRoute(
        string calldata route
    ) external view returns (bytes memory target, uint32 routeType);

    function isRouteBookClosed(
        string calldata label,
        string calldata namespace
    ) external view returns (bool closed);

    function isRouteBookClosed(string calldata xnsName) external view returns (bool closed);

    function getRouteKeyCount(
        string calldata label,
        string calldata namespace
    ) external view returns (uint256 count);

    function getRouteKeyCount(string calldata xnsName) external view returns (uint256 count);

    function getRouteKeys(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys);

    function getRouteKeys(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory keys);

    function getRouteEntries(
        string calldata label,
        string calldata namespace,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries);

    function getRouteEntries(
        string calldata xnsName,
        uint256 start,
        uint256 end
    ) external view returns (RouteEntry[] memory entries);

    function splitRoute(
        string calldata route
    )
        external
        pure
        returns (string memory label, string memory namespace, string memory routeLabel);

    function splitXNSName(
        string calldata xnsName
    ) external pure returns (string memory label, string memory namespace);

    function isValidRouteLabel(string calldata routeLabel) external pure returns (bool valid);
}
