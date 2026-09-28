// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IXNSMinimal} from "../interfaces/IXNSMinimal.sol";
import {IXNSRoutes} from "../interfaces/IXNSRoutes.sol";

/// @title SponsoredRoutes
/// @notice Example contract that owns an XNS name and publishes routes under it that can never
/// be changed or deactivated.
///
/// The contract registers `label AT namespace` for itself at deployment. Because XNS names are
/// non-transferable, this contract is the only address that can ever manage routes under that
/// name. Its only route-creating path is `sponsorRoute`, which uses `createRouteAndFreeze`, and
/// it has no way to call `updateRoute`, `deactivateRoute`, or any other route-changing function.
/// Every sponsored route is therefore frozen and active from creation and keeps resolving forever.
///
/// The owner decides which routes are created and what they point to, but has no power over a
/// route once it exists. Beneficiaries should verify their route after creation. Renouncing
/// ownership stops new sponsorships without affecting existing routes.
///
/// The guarantee relies on this contract being immutable: it is not upgradeable and cannot make
/// arbitrary calls. Adaptations must not add proxies, `delegatecall`, or generic call forwarding.
///
/// @dev Example code; not audited. The comments use AT instead of @ as solc treats @ as a
/// documentation tag in NatSpec.
contract SponsoredRoutes is Ownable2Step {
    /// @notice XNS Routes registry the sponsored routes are published in.
    IXNSRoutes public immutable XNS_ROUTES;

    /// @notice Label of the XNS name owned by this contract.
    string public xnsLabel;

    /// @notice Namespace of the XNS name owned by this contract.
    string public xnsNamespace;

    /// @notice Sets the owner and registries, then registers `label AT namespace` for this contract.
    ///
    /// **Requirements:**
    /// - `initialOwner`, `xnsContract` and `xnsRoutesContract` must not be the zero address.
    /// - `msg.value` must equal the XNS price for `namespace` exactly (query
    ///   `getNamespacePrice(namespace)`). XNS refunds any excess to the caller, and this contract
    ///   has no `receive()` function, so an overpayment reverts the deployment.
    /// - `label AT namespace` must be registrable on XNS.
    ///
    /// @param initialOwner Address allowed to sponsor routes and close the route book.
    /// @param xnsContract Address of the XNSv2 registry.
    /// @param xnsRoutesContract Address of the XNS Routes registry.
    /// @param label Label of the XNS name to register for this contract.
    /// @param namespace Namespace of the XNS name to register for this contract.
    constructor(
        address initialOwner,
        address xnsContract,
        address xnsRoutesContract,
        string memory label,
        string memory namespace
    ) payable Ownable(initialOwner) {
        require(xnsContract != address(0), "SponsoredRoutes: 0x XNS address");
        require(xnsRoutesContract != address(0), "SponsoredRoutes: 0x XNSRoutes");

        XNS_ROUTES = IXNSRoutes(xnsRoutesContract);
        xnsLabel = label;
        xnsNamespace = namespace;

        IXNSMinimal(xnsContract).registerName{value: msg.value}(label, namespace);
    }

    /// @notice Creates a frozen, active route `label AT namespace/routeLabel` under this
    /// contract's XNS name.
    ///
    /// The route is immediately resolvable and can never be changed or deactivated.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner.
    /// - All `XNSRoutes.createRouteAndFreeze` requirements (valid route label, non-empty target,
    ///   open route book, route must not exist).
    ///
    /// @param routeLabel Route label to create.
    /// @param target Opaque endpoint payload.
    /// @param routeType Off-chain interpretation hint (see `routeTypes/`).
    function sponsorRoute(
        string calldata routeLabel,
        bytes calldata target,
        uint32 routeType
    ) external onlyOwner {
        XNS_ROUTES.createRouteAndFreeze(xnsLabel, xnsNamespace, routeLabel, target, routeType);
    }

    /// @notice Permanently closes the route book of this contract's XNS name.
    ///
    /// After closing, no further routes can be sponsored. Existing routes are unaffected.
    ///
    /// **Requirements:**
    /// - `msg.sender` must be the owner.
    function closeRouteBook() external onlyOwner {
        XNS_ROUTES.closeRouteBook(xnsLabel, xnsNamespace);
    }
}
