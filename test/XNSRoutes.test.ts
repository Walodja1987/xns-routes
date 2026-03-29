import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import type { MockXNS, XNSRoutes } from "../typechain-types";

describe("XNSRoutes", function () {
  const { ethers } = hre;

  const XNS_NAME = "xns.action";
  const CHAIN = "eth";
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
    it("Should let the name owner create a route and emit RouteSet", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false),
      )
        .to.emit(routes, "RouteSet")
        .and.to.not.emit(routes, "RouteFrozen");

      expect(await routes.routeExists(XNS_NAME, CHAIN, ROUTE)).to.equal(true);
      const [target, isActive, isFrozen, routeType] = await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE);
      expect(target).to.equal(buildTarget);
      expect(isActive).to.equal(true);
      expect(isFrozen).to.equal(false);
      expect(routeType).to.equal(RT0);
    });

    it("Should emit RouteFrozen when freeze is true on create", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, true),
      )
        .to.emit(routes, "RouteSet")
        .and.to.emit(routes, "RouteFrozen");

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[2]).to.equal(true);
    });

    it("Should let the name owner update target and isActive when not frozen", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      const newTarget = other.address;
      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, ROUTE, newTarget, RT0, false, false),
      ).to.emit(routes, "RouteSet");

      const [target, isActive, isFrozen] = await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE);
      expect(target).to.equal(newTarget);
      expect(isActive).to.equal(false);
      expect(isFrozen).to.equal(false);
    });

    it("Should let the name owner update routeType when not frozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, 1, true, false),
      ).to.emit(routes, "RouteSet");

      const [, , , routeType] = await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE);
      expect(routeType).to.equal(1);
    });

    it("Should emit RouteFrozen when freeze is true on update", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, true),
      )
        .to.emit(routes, "RouteFrozen")
        .and.to.emit(routes, "RouteSet");

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[2]).to.equal(true);
    });

    it("Should revert with NotXnsNameOwner when caller is not XNS owner", async function () {
      const { routes, other, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(other).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with InvalidXnsName when xnsName is empty", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute("", CHAIN, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidXnsName");
    });

    it("Should revert with InvalidXnsName when XNS resolves owner to zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const orphan = "orphan.test";

      await expect(
        routes.connect(owner).createRoute(orphan, CHAIN, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidXnsName");
    });

    it("Should revert with InvalidChain when XNS marks chain label invalid", async function () {
      const { routes, owner, mockXns, buildTarget } = await loadFixture(deployFixture);
      const badChain = "bad-chain";
      await mockXns.setLabelInvalid(badChain, true);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, badChain, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidChain");
    });

    it("Should allow empty chain without InvalidChain (chain-agnostic route)", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      const globalRoute = "my-wallet";

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, "", globalRoute, buildTarget, RT0, true, false),
      ).to.emit(routes, "RouteSet");

      expect(await routes.routeExists(XNS_NAME, "", globalRoute)).to.equal(true);
      expect(await routes.getRoute(XNS_NAME, "", globalRoute)).to.equal(buildTarget);
      expect(await routes.routeExists(XNS_NAME, CHAIN, globalRoute)).to.equal(false);
      await expect(routes.getRoute(XNS_NAME, CHAIN, globalRoute)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );

      await routes
        .connect(owner)
        .createRoute(XNS_NAME, CHAIN, globalRoute, other.address, RT0, true, false);
      expect(await routes.getRoute(XNS_NAME, "", globalRoute)).to.equal(buildTarget);
      expect(await routes.getRoute(XNS_NAME, CHAIN, globalRoute)).to.equal(other.address);
    });

    it("Should revert with InvalidRoute when XNS marks route label invalid", async function () {
      const { routes, owner, mockXns, buildTarget } = await loadFixture(deployFixture);
      const badRoute = "bad-route";
      await mockXns.setLabelInvalid(badRoute, true);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, badRoute, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidRoute");
    });

    it("Should revert with InvalidTarget when target is zero", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, ethers.ZeroAddress, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "InvalidTarget");
    });

    it("Should revert with RouteBookFrozen after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with CannotUpdateFrozenRoute when route is frozen", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, true);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, ROUTE, other.address, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });

    it("Should keep routes independent per xnsName, chain, and route", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      const t1 = buildTarget;
      const t2 = other.address;

      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, t1, RT0, true, false);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, "other-route", t2, RT0, true, false);
      await routes.connect(owner).createRoute(XNS_NAME, "base", ROUTE, t2, RT0, true, false);
      await routes.connect(other).createRoute(OTHER_BASE, CHAIN, ROUTE, t2, RT0, false, false);

      expect(await routes.getRoute(XNS_NAME, CHAIN, ROUTE)).to.equal(t1);
      expect(await routes.getRoute(XNS_NAME, CHAIN, "other-route")).to.equal(t2);
      expect(await routes.getRoute(XNS_NAME, "base", ROUTE)).to.equal(t2);
      expect(await routes.getRoute(OTHER_BASE, CHAIN, ROUTE)).to.equal(t2);
    });

    it("Should revert with RouteAlreadyExists when createRoute is called twice for same key", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteAlreadyExists");
    });

    it("Should revert with RouteNotFound when updateRoute is called for a missing route", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, "missing", buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });
  });

  describe("activateRoute and deactivateRoute", function () {
    it("Should deactivate, emit RouteActivationSet, and set isActive false", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE))
        .to.emit(routes, "RouteActivationSet")
        .withArgs(XNS_NAME, CHAIN, ROUTE, false);

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[1]).to.equal(false);
    });

    it("Should activate after deactivate and emit RouteActivationSet", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE);

      await expect(routes.connect(owner).activateRoute(XNS_NAME, CHAIN, ROUTE))
        .to.emit(routes, "RouteActivationSet")
        .withArgs(XNS_NAME, CHAIN, ROUTE, true);

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[1]).to.equal(true);
    });

    it("Should not emit RouteActivationSet when deactivate called twice", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE);

      const filter = routes.filters.RouteActivationSet();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should not emit RouteActivationSet when activate called while already active", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteActivationSet();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).activateRoute(XNS_NAME, CHAIN, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should succeed after route freeze", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, true);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE)).to.emit(
        routes,
        "RouteActivationSet",
      );
      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[1]).to.equal(false);
    });

    it("Should succeed after route book freeze", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE)).to.emit(
        routes,
        "RouteActivationSet",
      );
    });

    it("Should revert with NotXnsNameOwner for wrong caller", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).deactivateRoute(XNS_NAME, CHAIN, ROUTE),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, "missing"),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });
  });

  describe("deleteRoute", function () {
    it("Should emit RouteDeleted, clear the route, and allow createRoute again", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).deleteRoute(XNS_NAME, CHAIN, ROUTE))
        .to.emit(routes, "RouteDeleted")
        .withArgs(XNS_NAME, CHAIN, ROUTE);

      expect(await routes.routeExists(XNS_NAME, CHAIN, ROUTE)).to.equal(false);
      await expect(routes.getRoute(XNS_NAME, CHAIN, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, other.address, RT0, false, false),
      ).to.emit(routes, "RouteSet");

      expect(await routes.getRoute(XNS_NAME, CHAIN, ROUTE)).to.equal(other.address);
    });

    it("Should revert with CannotDeleteFrozenRoute after freezeRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, CHAIN, ROUTE),
      ).to.be.revertedWithCustomError(routes, "CannotDeleteFrozenRoute");
    });

    it("Should revert with RouteBookFrozen after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, CHAIN, ROUTE),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with NotXnsNameOwner for wrong caller", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).deleteRoute(XNS_NAME, CHAIN, ROUTE),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, CHAIN, "missing"),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });
  });

  describe("updateTarget and updateRouteType", function () {
    it("Should update target and emit RouteSet", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).updateTarget(XNS_NAME, CHAIN, ROUTE, other.address))
        .to.emit(routes, "RouteSet")
        .withArgs(XNS_NAME, CHAIN, ROUTE, other.address, true, false, RT0);

      expect(await routes.getRoute(XNS_NAME, CHAIN, ROUTE)).to.equal(other.address);
    });

    it("Should not emit RouteSet when updateTarget is no-op", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteSet();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).updateTarget(XNS_NAME, CHAIN, ROUTE, buildTarget);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert updateTarget with InvalidTarget when newTarget is zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, CHAIN, ROUTE, ethers.ZeroAddress),
      ).to.be.revertedWithCustomError(routes, "InvalidTarget");
    });

    it("Should update routeType and emit RouteSet", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).updateRouteType(XNS_NAME, CHAIN, ROUTE, 7))
        .to.emit(routes, "RouteSet")
        .withArgs(XNS_NAME, CHAIN, ROUTE, buildTarget, true, false, 7);

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[3]).to.equal(7);
    });

    it("Should not emit RouteSet when updateRouteType is no-op", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      const filter = routes.filters.RouteSet();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).updateRouteType(XNS_NAME, CHAIN, ROUTE, RT0);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner for updateTarget", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(
        routes.connect(other).updateTarget(XNS_NAME, CHAIN, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "NotXnsNameOwner");
    });

    it("Should revert with RouteNotFound for updateTarget when route missing", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, CHAIN, "missing", buildTarget),
      ).to.be.revertedWithCustomError(routes, "RouteNotFound");
    });

    it("Should revert with CannotUpdateFrozenRoute for updateTarget after freezeRoute", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, CHAIN, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });

    it("Should revert with RouteBookFrozen for updateTarget after freezeRouteBook", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).updateTarget(XNS_NAME, CHAIN, ROUTE, other.address),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with RouteBookFrozen for updateRouteType after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).updateRouteType(XNS_NAME, CHAIN, ROUTE, 1),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");
    });

    it("Should revert with CannotUpdateFrozenRoute for updateRouteType after freezeRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE);

      await expect(
        routes.connect(owner).updateRouteType(XNS_NAME, CHAIN, ROUTE, 1),
      ).to.be.revertedWithCustomError(routes, "CannotUpdateFrozenRoute");
    });
  });

  describe("freezeRoute", function () {
    it("Should freeze route and emit RouteFrozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE)).to.emit(
        routes,
        "RouteFrozen",
      );

      expect((await routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE))[2]).to.equal(true);
    });

    it("Should not emit RouteFrozen on second call", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE);

      const filter = routes.filters.RouteFrozen();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, ROUTE);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);

      await expect(routes.connect(other).freezeRoute(XNS_NAME, CHAIN, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "NotXnsNameOwner",
      );
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(routes.connect(owner).freezeRoute(XNS_NAME, CHAIN, "nope")).to.be.revertedWithCustomError(
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

      expect(await routes.routeBookFrozen(xnsNameKey)).to.equal(true);
    });

    it("Should block createRoute, updateRoute, and deleteRoute but allow deactivateRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, true, false);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, CHAIN, "new-one", buildTarget, RT0, true, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(
        routes.connect(owner).updateRoute(XNS_NAME, CHAIN, ROUTE, buildTarget, RT0, false, false),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(
        routes.connect(owner).deleteRoute(XNS_NAME, CHAIN, ROUTE),
      ).to.be.revertedWithCustomError(routes, "RouteBookFrozen");

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, CHAIN, ROUTE)).to.emit(
        routes,
        "RouteActivationSet",
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

  describe("getRoute / getRouteInfo / routeExists", function () {
    it("Should revert getRoute and getRouteInfo with RouteNotFound when missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      expect(await routes.routeExists(XNS_NAME, CHAIN, ROUTE)).to.equal(false);

      await expect(routes.getRoute(XNS_NAME, CHAIN, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );
      await expect(routes.getRouteInfo(XNS_NAME, CHAIN, ROUTE)).to.be.revertedWithCustomError(
        routes,
        "RouteNotFound",
      );
    });
  });
});
