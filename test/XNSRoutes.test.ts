import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import type { MockXNS, XNSRoutes } from "../typechain-types";

describe("XNSRoutes", function () {
  const { ethers } = hre;

  const XNS_NAME = "xns.action";
  const ROUTE_PREFIX = "eth";
  const ROUTE = "register-name";
  const OTHER_BASE = "other.action";
  /** Default `routeType` in tests; semantics are offchain */
  const RT0 = 0;

  interface Fixture {
    routes: XNSRoutes;
    mockXns: MockXNS;
    owner: SignerWithAddress;
    other: SignerWithAddress;
    buildTarget: string;
  }

  async function deployFixture(): Promise<Fixture> {
    const [, owner, other] = await ethers.getSigners();
    const mockXns = await ethers.deployContract("MockXNS");
    await mockXns.waitForDeployment();
    const mockAddr = String(mockXns.target);
    const routes = await ethers.deployContract("XNSRoutes", [mockAddr], { value: 0n });
    await routes.waitForDeployment();

    await mockXns.setResolution(XNS_NAME, owner.address);
    await mockXns.setResolution(OTHER_BASE, other.address);

    const buildTarget = ethers.Wallet.createRandom().address;

    return {
      routes,
      mockXns,
      owner,
      other,
      buildTarget,
    };
  }

  describe("constructor", function () {
    it("Should store the XNS registry and expose it via XNS()", async function () {
      const { routes, mockXns } = await loadFixture(deployFixture);
      expect(await routes.XNS()).to.equal(String(mockXns.target));
    });

    it("Should revert with ZeroAddress when xns_ is zero address", async function () {
      const XNSRoutes = await ethers.getContractFactory("XNSRoutes");
      await expect(XNSRoutes.deploy(ethers.ZeroAddress, { value: 0n })).to.be.revertedWithCustomError(
        XNSRoutes,
        "ZeroAddress",
      );
    });

    it("Should register routes.xns to the deployed registry via constructor", async function () {
      const { routes, mockXns } = await loadFixture(deployFixture);
      const resolved = await mockXns.getFunction("getAddress(string)")("routes.xns");
      expect(resolved).to.equal(String(routes.target));
    });
  });

  describe("createRoute and updateRoute", function () {
    it("Should let the name owner create a route and emit RouteCreated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      )
        .to.emit(routes, "RouteCreated")
        .and.to.not.emit(routes, "RouteFrozen");

      expect(await routes.routeExists(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.equal(true);
      const [target, isActive, isFrozen, routeType] = await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE);
      expect(target).to.equal(buildTarget);
      expect(isActive).to.equal(true);
      expect(isFrozen).to.equal(false);
      expect(routeType).to.equal(RT0);
    });

    it("Should emit RouteFrozen when freeze is true on create", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, true),
      )
        .to.emit(routes, "RouteCreated")
        .and.to.emit(routes, "RouteFrozen");

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[2]).to.equal(true);
    });

    it("Should let the name owner update target and isActive when not frozen", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      const newTarget = other.address;
      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, newTarget, RT0, false, false),
      ).to.emit(routes, "RouteUpdated");

      const [target, isActive, isFrozen] = await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE);
      expect(target).to.equal(newTarget);
      expect(isActive).to.equal(false);
      expect(isFrozen).to.equal(false);
    });

    it("Should let the name owner update routeType when not frozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, 1, true, false),
      ).to.emit(routes, "RouteUpdated");

      const [, , , routeType] = await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE);
      expect(routeType).to.equal(1);
    });

    it("Should emit RouteFrozen when freeze is true on update", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, true),
      )
        .to.emit(routes, "RouteFrozen")
        .and.to.emit(routes, "RouteUpdated");

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[2]).to.equal(true);
    });

    it("Should revert with NotXnsNameOwner when caller is not XNS owner", async function () {
      const { routes, other, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(other).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with InvalidXnsName when xnsName is empty", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute("", ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidXnsName");
    });

    it("Should revert with InvalidXnsName when XNS resolves owner to zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const orphan = "orphan.test";

      await expect(
        routes.connect(owner).createRoute(orphan, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidXnsName");
    });

    it("Should revert with InvalidRoutePrefix when XNS marks routePrefix label invalid", async function () {
      const { routes, owner, mockXns, buildTarget } = await loadFixture(deployFixture);
      const badRoutePrefix = "bad-prefix";
      await mockXns.setLabelInvalid(badRoutePrefix, true);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, badRoutePrefix, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidRoutePrefix");
    });

    it("Should allow empty routePrefix without InvalidRoutePrefix (single-segment route)", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      const globalRoute = "my-wallet";

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, "", globalRoute, buildTarget, RT0, true, false),
      ).to.emit(routes, "RouteCreated");

      expect(await routes.routeExists(XNS_NAME, "", globalRoute)).to.equal(true);
      expect((await routes.getRouteInfo(XNS_NAME, "", globalRoute))[0]).to.equal(buildTarget);
      expect(await routes.routeExists(XNS_NAME, ROUTE_PREFIX, globalRoute)).to.equal(false);
      await expect(routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, globalRoute)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );

      await routes
        .connect(owner)
        .createRoute(XNS_NAME, ROUTE_PREFIX, globalRoute, other.address, RT0, true, false);
      expect((await routes.getRouteInfo(XNS_NAME, "", globalRoute))[0]).to.equal(buildTarget);
      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, globalRoute))[0]).to.equal(other.address);
    });

    it("Should revert with InvalidRoute when XNS marks route label invalid", async function () {
      const { routes, owner, mockXns, buildTarget } = await loadFixture(deployFixture);
      const badRoute = "bad-route";
      await mockXns.setLabelInvalid(badRoute, true);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, badRoute, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidRoute");
    });

    it("Should revert with InvalidTarget when target is zero", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, ethers.ZeroAddress, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidTarget");
    });

    it("Should revert with RouteBookFrozen after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with CannotUpdateFrozenRoute when route is frozen", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, true);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });

    it("Should keep routes independent per xnsName, routePrefix, and route", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      const t1 = buildTarget;
      const t2 = other.address;

      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, t1, RT0, true, false);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, "other-route", t2, RT0, true, false);
      await routes.connect(owner).createRoute(XNS_NAME, "base", ROUTE, t2, RT0, true, false);
      await routes.connect(other).createRoute(OTHER_BASE, ROUTE_PREFIX, ROUTE, t2, RT0, false, false);

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[0]).to.equal(t1);
      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, "other-route"))[0]).to.equal(t2);
      expect((await routes.getRouteInfo(XNS_NAME, "base", ROUTE))[0]).to.equal(t2);
      expect((await routes.getRouteInfo(OTHER_BASE, ROUTE_PREFIX, ROUTE))[0]).to.equal(t2);
    });

    it("Should revert with RouteAlreadyExists when createRoute is called twice for same key", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteAlreadyExists");
    });

    it("Should revert with RouteNotFound when updateRoute is called for a missing route", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, "missing", buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });

    it("Should revert with InvalidRoute when updateRoute uses empty prefix and route contains colon (alias encoding)", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      const aliasRoute = `${ROUTE_PREFIX}:${ROUTE}`;
      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, "", aliasRoute, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidRoute");
    });
  });

  describe("activateRoute and deactivateRoute", function () {
    it("Should deactivate, emit RouteActiveStatusUpdated, and set isActive false", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(XNS_NAME, ROUTE_PREFIX, ROUTE, false);

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[1]).to.equal(false);
    });

    it("Should activate after deactivate and emit RouteActiveStatusUpdated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      await expect(routes.connect(owner).activateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(XNS_NAME, ROUTE_PREFIX, ROUTE, true);

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[1]).to.equal(true);
    });

    it("Should not emit RouteActiveStatusUpdated when deactivate called twice", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      const filter = routes.filters.RouteActiveStatusUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should not emit RouteActiveStatusUpdated when activate called while already active", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteActiveStatusUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).activateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should succeed after route freeze", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, true);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[1]).to.equal(false);
    });

    it("Should succeed after route book freeze", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
    });

    it("Should revert with NotXnsNameOwner for wrong caller", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, "missing"),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });
  });

  describe("deleteRoute", function () {
    it("Should emit RouteDeleted, clear the route, and allow createRoute again", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).deleteRoute(XNS_NAME, ROUTE_PREFIX, ROUTE))
        .to.emit(routes, "RouteDeleted")
        .withArgs(XNS_NAME, ROUTE_PREFIX, ROUTE);

      expect(await routes.routeExists(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.equal(false);
      await expect(routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address, RT0, false, false),
      ).to.emit(routes, "RouteCreated");

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[0]).to.equal(other.address);
    });

    it("Should revert with CannotDeleteFrozenRoute after freezeRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, ROUTE_PREFIX, ROUTE),
      ).to.be.revertedWithCustomError(routes, "CannotDeleteFrozenRoute");
    });

    it("Should revert with RouteBookFrozen after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, ROUTE_PREFIX, ROUTE),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with NotXnsNameOwner for wrong caller", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).deleteRoute(XNS_NAME, ROUTE_PREFIX, ROUTE),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, ROUTE_PREFIX, "missing"),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });
  });

  describe("updateTarget and updateRouteType", function () {
    it("Should update target and emit RouteTargetUpdated", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address))
        .to.emit(routes, "RouteTargetUpdated")
        .withArgs(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address);

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[0]).to.equal(other.address);
    });

    it("Should not emit RouteTargetUpdated when updateTarget is no-op", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteTargetUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert updateTarget with InvalidTarget when newTarget is zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, ethers.ZeroAddress),
      ).to.be.revertedWithCustomError(routes, "InvalidTarget");
    });

    it("Should update routeType and emit RouteTypeUpdated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).updateRouteType(XNS_NAME, ROUTE_PREFIX, ROUTE, 7))
        .to.emit(routes, "RouteTypeUpdated")
        .withArgs(XNS_NAME, ROUTE_PREFIX, ROUTE, 7);

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[3]).to.equal(7);
    });

    it("Should not emit RouteTypeUpdated when updateRouteType is no-op", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteTypeUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).updateRouteType(XNS_NAME, ROUTE_PREFIX, ROUTE, RT0);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner for updateTarget", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound for updateTarget when route missing", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, "missing", buildTarget),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });

    it("Should revert with CannotUpdateFrozenRoute for updateTarget after freezeRoute", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });

    it("Should revert with RouteBookFrozen for updateTarget after freezeRouteBook", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, ROUTE_PREFIX, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with RouteBookFrozen for updateRouteType after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).updateRouteType(XNS_NAME, ROUTE_PREFIX, ROUTE, 1),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with CannotUpdateFrozenRoute for updateRouteType after freezeRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      await expect(
        routes.connect(owner).updateRouteType(XNS_NAME, ROUTE_PREFIX, ROUTE, 1),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });
  });

  describe("freezeRoute", function () {
    it("Should freeze route and emit RouteFrozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.emit(
        routes,
        "RouteFrozen",
      );

      expect((await routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE))[2]).to.equal(true);
    });

    it("Should not emit RouteFrozen on second call", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);

      const filter = routes.filters.RouteFrozen();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(other).freezeRoute(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "NotXnsNameOwner",
      );
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(routes.connect(owner).freezeRoute(XNS_NAME, ROUTE_PREFIX, "nope")).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );
    });
  });

  describe("freezeRouteBook", function () {
    it("Should set routeBookFrozen and emit RouteBookFrozenForName", async function () {
      const { routes, owner } = await loadFixture(deployFixture);
      const xnsNameKey = ethers.keccak256(ethers.toUtf8Bytes(XNS_NAME));

      await expect(routes.connect(owner).freezeRouteBook(XNS_NAME)).to.emit(
        routes,
        "RouteBookFrozenForName",
      );

      expect(await routes.isRouteBookFrozen(XNS_NAME)).to.equal(true);
    });

    it("Should block createRoute, updateRoute, and deleteRoute but allow deactivateRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_PREFIX, "new-one", buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE, buildTarget, RT0, false, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, ROUTE_PREFIX, ROUTE),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
    });

    it("Should not emit RouteBookFrozenForName on second call", async function () {
      const { routes, owner } = await loadFixture(deployFixture);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      const filter = routes.filters.RouteBookFrozenForName();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).freezeRouteBook(XNS_NAME);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner", async function () {
      const { routes, other } = await loadFixture(deployFixture);

      await expect(routes.connect(other).freezeRouteBook(XNS_NAME)).to.be.revertedWithCustomError(
        routes,
        "NotXnsNameOwner",
      );
    });
  });

  describe("getRouteInfo / routeExists", function () {
    it("Should revert getRouteInfo with RouteNotFound when missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      expect(await routes.routeExists(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.equal(false);

      await expect(routes.getRouteInfo(XNS_NAME, ROUTE_PREFIX, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );
    });

    it("Should revert getRouteInfo and routeExists with InvalidRoute for colon in route when prefix is empty", async function () {
      const { routes } = await loadFixture(deployFixture);
      const aliasRoute = `${ROUTE_PREFIX}:${ROUTE}`;
      await expect(routes.getRouteInfo(XNS_NAME, "", aliasRoute)).to.be.revertedWithCustomError(
        routes,
        "InvalidRoute",
      );
      await expect(routes.routeExists(XNS_NAME, "", aliasRoute)).to.be.revertedWithCustomError(
        routes,
        "InvalidRoute",
      );
    });
  });
});
