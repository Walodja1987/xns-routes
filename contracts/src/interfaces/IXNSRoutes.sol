// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IXNSRoutes
/// @notice Interface for the `XNSRoutes` route registry (XNSv2 `label AT namespace/route` format).
interface IXNSRoutes {
    struct RouteRecord {
        address target;
        uint32 routeType;
        bool isActive;
        address activeController;
        string routeLabel;
    }

    struct RouteEntry {
        bytes32 routeKey;
        RouteRecord record;
    }

    event RouteCreated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        address indexed target,
        uint32 routeType,
        bool isActive,
        address activeController
    );

    event RouteActiveStatusUpdated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        bool isActive
    );

    event RouteBookFrozen(bytes32 indexed xnsNameKey, string label, string namespace);

    event ActiveControllerTransferInitiated(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        address indexed pendingActiveController
    );

    event ActiveControllerTransferAccepted(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        address previousActiveController,
        address indexed newActiveController
    );

    event ActiveControllerTransferCancelled(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel,
        address indexed cancelledPendingActiveController
    );

    event ActiveControllerRenounced(
        bytes32 indexed xnsNameKey,
        bytes32 indexed routeKey,
        string label,
        string namespace,
        string routeLabel
    );

    function NO_ACTIVE_CONTROLLER() external view returns (address);

    function XNS() external view returns (address);

    function createRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        address target,
        uint32 routeType
    ) external;

    function createRouteWithController(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        address target,
        uint32 routeType,
        address activeController
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

    function initiateActiveControllerTransfer(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel,
        address newActiveController
    ) external;

    function acceptActiveController(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function cancelActiveControllerTransfer(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function renounceActiveControl(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external;

    function freezeRouteBook(string calldata label, string calldata namespace) external;

    function freezeRouteBook(string calldata xnsName) external;

    function getRouteRecord(bytes32 routeKey) external view returns (RouteRecord memory record);

    function getRouteRecord(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (RouteRecord memory record);

    function getRouteRecord(string calldata route) external view returns (RouteRecord memory record);

    function resolveRouteIfActive(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType);

    function resolveRouteIfActive(
        string calldata route
    ) external view returns (address target, uint32 routeType);

    function resolveRoute(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (address target, uint32 routeType);

    function resolveRoute(
        string calldata route
    ) external view returns (address target, uint32 routeType);

    function isRouteBookFrozen(
        string calldata label,
        string calldata namespace
    ) external view returns (bool frozen);

    function isRouteBookFrozen(string calldata xnsName) external view returns (bool frozen);

    function pendingActiveController(
        string calldata label,
        string calldata namespace,
        string calldata routeLabel
    ) external view returns (address pending);

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
    ) external pure returns (string memory label, string memory namespace, string memory routeLabel);

    function splitXNSName(
        string calldata xnsName
    ) external pure returns (string memory label, string memory namespace);

    function isValidRouteLabel(string calldata routeLabel) external pure returns (bool valid);
}
