import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import type { MockXNS, XNSRoutes } from "../typechain-types";

describe("XNSRoutes", function () {
  const { ethers } = hre;

  const XNS_NAME = "xns.action";
  const ROUTE_SCOPE = "eth";
  const ROUTE_LABEL = "register-name";
  const OTHER_BASE = "other.action";
  /** Default `routeType` in tests; semantics are offchain */
  const RT0 = 0;
  const NO_ACTIVE_CONTROLLER = "0x000000000000000000000000000000000000dEaD";

  /** Matches `require(..., "XNSRoutes: ...")` in `XNSRoutes.sol`. */
  const XR = {
    zeroXnsAddress: "XNSRoutes: 0x XNS address",
    invalidXnsName: "XNSRoutes: invalid XNS name",
    invalidRouteScope: "XNSRoutes: invalid route scope",
    invalidRouteLabel: "XNSRoutes: invalid route label",
    invalidTarget: "XNSRoutes: invalid target",
    invalidActiveController: "XNSRoutes: invalid active controller",
    notXnsNameOwner: "XNSRoutes: not XNS name owner",
    notActiveController: "XNSRoutes: not active controller",
    activeControlRenounced: "XNSRoutes: active control renounced",
    sameActiveController: "XNSRoutes: same active controller",
    useRenounceActiveControl: "XNSRoutes: use renounceActiveControl",
    noPendingTransfer: "XNSRoutes: no pending transfer",
    notPendingActiveController: "XNSRoutes: not pending active controller",
    routeNotFound: "XNSRoutes: route not found",
    routeInactive: "XNSRoutes: route inactive",
    routeBookFrozen: "XNSRoutes: route book frozen",
    routeAlreadyExists: "XNSRoutes: route already exists",
    invalidRoute: "XNSRoutes: invalid route",
    invalidRouteKeySlice: "XNSRoutes: invalid route key slice",
  } as const;

  /** Matches `_canonicalizeXNSName`: dotless `label` → `label.x`. */
  function canonicalXnsName(xnsName: string): string {
    for (let i = 0; i < xnsName.length; i++) {
      if (xnsName[i] === ".") return xnsName;
    }
    return `${xnsName}.x`;
  }

  /** Matches `XNSRoutes._xnsNameKey` / `keccak256(bytes(canonical xnsName))`. */
  function xnsNameKey(xnsName: string): string {
    return ethers.keccak256(ethers.toUtf8Bytes(canonicalXnsName(xnsName)));
  }

  /** Matches `XNSRoutes._routeKey` `abi.encodePacked` layout (canonical `xnsName`). */
  function routeStorageKey(xnsName: string, routeScope: string, routeLabel: string): string {
    const c = canonicalXnsName(xnsName);
    if (routeScope === "") {
      return ethers.solidityPackedKeccak256(["string", "string", "string"], [c, "/", routeLabel]);
    }
    return ethers.solidityPackedKeccak256(
      ["string", "string", "string", "string", "string"],
      [c, "/", routeScope, ":", routeLabel],
    );
  }

  /** Disambiguate ethers overload: `getRouteRecord(bytes32)`. */
  async function getRouteRecordByKey(routes: XNSRoutes, routeKey: string) {
    return routes["getRouteRecord(bytes32)"](routeKey);
  }

  /** Disambiguate ethers overload: `getRouteRecord(string)` (route). */
  async function getRouteRecordByRoute(routes: XNSRoutes, route: string) {
    return routes["getRouteRecord(string)"](route);
  }

  /** Disambiguate ethers overload: `resolveRouteIfActive(string)` (route). */
  async function resolveRouteIfActiveByRoute(routes: XNSRoutes, route: string) {
    return routes["resolveRouteIfActive(string)"](route);
  }

  /** Disambiguate ethers overload: `resolveRoute(string)` (route). */
  async function resolveRouteByRoute(routes: XNSRoutes, route: string) {
    return routes["resolveRoute(string)"](route);
  }

  /** `getRouteRecord(routeKey)` returns a struct; destructure as tuple in tests. */
  async function getRouteRecordSingle(routes: XNSRoutes, routeKey: string) {
    const r = await getRouteRecordByKey(routes, routeKey);
    return [r.target, r.routeType, r.isActive, r.activeController] as const;
  }

  function isLiveTarget(target: string): boolean {
    return target !== ethers.ZeroAddress;
  }

  async function getRouteRecordTuple(
    routes: XNSRoutes,
    xnsName: string,
    routeScope: string,
    routeLabel: string,
  ) {
    const r = await routes.getRouteRecord(xnsName, routeScope, routeLabel);
    return [r.target, r.routeType, r.isActive, r.activeController] as const;
  }

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
    const routes = await ethers.deployContract("XNSRoutes", [mockAddr], {
      value: 0n,
    });
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

    it("Should revert with zero XNS address when xns_ is zero address", async function () {
      const XNSRoutes = await ethers.getContractFactory("XNSRoutes");
      await expect(XNSRoutes.deploy(ethers.ZeroAddress, { value: 0n })).to.be.revertedWith(
        XR.zeroXnsAddress,
      );
    });

    it("Should register routes.xns to the deployed registry via constructor", async function () {
      const { routes, mockXns } = await loadFixture(deployFixture);
      const resolved = await mockXns.getFunction("getAddress(string)")("routes.xns");
      expect(resolved).to.equal(String(routes.target));
    });
  });

  describe("createRoute", function () {
    it("Should let the name owner create a route and emit RouteCreated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      )
        .to.emit(routes, "RouteCreated")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          buildTarget,
          RT0,
          true,
          owner.address,
        );

      expect(isLiveTarget((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).target)).to.equal(true);
      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(record.target).to.equal(buildTarget);
      expect(record.isActive).to.equal(true);
      expect(record.routeType).to.equal(RT0);
      expect(record.activeController).to.equal(owner.address);
    });

    it("Should revert with NotXnsNameOwner when caller is not XNS owner", async function () {
      const { routes, other, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(other).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should revert with InvalidXnsName when xnsName is empty", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute("", ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.invalidXnsName);
    });

    it("Should revert with NotXnsNameOwner when XNS resolves owner to zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const orphan = "orphan.test";

      await expect(
        routes.connect(owner).createRoute(orphan, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should revert with InvalidRouteScope when routeScope exceeds 20 chars", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const badRoutePrefix = "a".repeat(21);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, badRoutePrefix, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.invalidRouteScope);
    });

    it("Should allow empty routeScope without InvalidRouteScope (single-segment route)", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      const globalRoute = "my-wallet";

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, "", globalRoute, buildTarget, RT0),
      ).to.emit(routes, "RouteCreated");

      expect(isLiveTarget((await routes.getRouteRecord(XNS_NAME, "", globalRoute)).target)).to.equal(true);
      expect((await routes.getRouteRecord(XNS_NAME, "", globalRoute)).target).to.equal(buildTarget);
      expect(isLiveTarget((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, globalRoute)).target)).to.equal(false);
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, globalRoute)).target).to.equal(
        ethers.ZeroAddress,
      );

      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, globalRoute, other.address, RT0);
      expect((await routes.getRouteRecord(XNS_NAME, "", globalRoute)).target).to.equal(buildTarget);
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, globalRoute)).target).to.equal(
        other.address,
      );
    });

    it("Should allow route length up to 32 chars and reject >32", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const route32 = "a".repeat(32);
      const route33 = "a".repeat(33);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, route32, buildTarget, RT0),
      ).to.emit(routes, "RouteCreated");

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, route33, buildTarget, RT0),
      ).to.be.revertedWith(XR.invalidRouteLabel);
    });

    it("Should revert with InvalidTarget when target is zero", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, ethers.ZeroAddress, RT0),
      ).to.be.revertedWith(XR.invalidTarget);
    });

    it("Should revert with RouteBookFrozen after freezeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeBookFrozen);
    });

    it("Should keep routes independent per xnsName, routeScope, and route", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      const t1 = buildTarget;
      const t2 = other.address;

      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, t1, RT0);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, "other-route", t2, RT0);
      await routes.connect(owner).createRoute(XNS_NAME, "base", ROUTE_LABEL, t2, RT0);
      await routes.connect(other).createRouteWithController(
        OTHER_BASE,
        ROUTE_SCOPE,
        ROUTE_LABEL,
        t2,
        RT0,
        other.address,
      );

      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).target).to.equal(t1);
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, "other-route")).target).to.equal(t2);
      expect((await routes.getRouteRecord(XNS_NAME, "base", ROUTE_LABEL)).target).to.equal(t2);
      expect((await routes.getRouteRecord(OTHER_BASE, ROUTE_SCOPE, ROUTE_LABEL)).target).to.equal(t2);
    });

    it("Should revert with RouteAlreadyExists when createRoute is called twice for same key", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);
    });
  });

  describe("createRouteWithController", function () {
    it("Should create route with explicit activeController", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes
          .connect(owner)
          .createRouteWithController(
            XNS_NAME,
            ROUTE_SCOPE,
            ROUTE_LABEL,
            buildTarget,
            RT0,
            other.address,
          ),
      )
        .to.emit(routes, "RouteCreated")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          buildTarget,
          RT0,
          true,
          other.address,
        );

      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(record.target).to.equal(buildTarget);
      expect(record.isActive).to.equal(true);
      expect(record.activeController).to.equal(other.address);
    });

    it("Should revert with InvalidActiveController when activeController is zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes
          .connect(owner)
          .createRouteWithController(
            XNS_NAME,
            ROUTE_SCOPE,
            ROUTE_LABEL,
            buildTarget,
            RT0,
            ethers.ZeroAddress,
          ),
      ).to.be.revertedWith(XR.invalidActiveController);
    });
  });

  describe("activateRoute and deactivateRoute", function () {
    it("Should deactivate, emit RouteActiveStatusUpdated, and set isActive false", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          false,
        );

      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).isActive).to.equal(false);
    });

    it("Should activate after deactivate and emit RouteActiveStatusUpdated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      await expect(routes.connect(owner).activateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          true,
        );

      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).isActive).to.equal(true);
    });

    it("Should not emit RouteActiveStatusUpdated when deactivate called twice", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      const filter = routes.filters.RouteActiveStatusUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should not emit RouteActiveStatusUpdated when activate called while already active", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const filter = routes.filters.RouteActiveStatusUpdated();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).activateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should succeed after route book freeze", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).isActive).to.equal(false);
    });

    it("Should revert with NotActiveController for wrong caller", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(other).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notActiveController);
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, "missing"),
      ).to.be.revertedWith(XR.routeNotFound);
    });
  });

  describe("activeController", function () {
    it("Should let activeController toggle without being the XNS name owner", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes
        .connect(owner)
        .createRouteWithController(
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          buildTarget,
          RT0,
          other.address,
        );

      await expect(routes.connect(other).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).isActive).to.equal(false);
    });

    it("Should revert when name owner toggles active status but is not activeController", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes
        .connect(owner)
        .createRouteWithController(
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          buildTarget,
          RT0,
          other.address,
        );

      await expect(
        routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notActiveController);
    });
  });

  describe("activeController transfer and renounce", function () {
    async function createDefaultRoute(fixture: Fixture) {
      const { routes, owner, buildTarget } = fixture;
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
    }

    it("Should transfer activeController in two steps", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, other } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes
          .connect(owner)
          .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, other.address),
      )
        .to.emit(routes, "ActiveControllerTransferInitiated")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          other.address,
        );

      expect(
        await routes.pendingActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.equal(other.address);

      await expect(routes.connect(other).acceptActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "ActiveControllerTransferAccepted")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          owner.address,
          other.address,
        );

      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(record.activeController).to.equal(other.address);
      expect(await routes.pendingActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.equal(
        ethers.ZeroAddress,
      );
    });

    it("Should let the current controller cancel a pending transfer", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, other } = fixture;
      await createDefaultRoute(fixture);

      await routes
        .connect(owner)
        .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, other.address);

      await expect(
        routes.connect(owner).cancelActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      )
        .to.emit(routes, "ActiveControllerTransferCancelled")
        .withArgs(
          xnsNameKey(XNS_NAME),
          routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
          XNS_NAME,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          other.address,
        );

      expect(await routes.pendingActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.equal(
        ethers.ZeroAddress,
      );
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).activeController).to.equal(
        owner.address,
      );
    });

    it("Should replace an existing pending transfer", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, other } = fixture;
      const [, , , third] = await ethers.getSigners();
      await createDefaultRoute(fixture);

      await routes
        .connect(owner)
        .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, other.address);
      await routes
        .connect(owner)
        .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, third.address);

      expect(await routes.pendingActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.equal(
        third.address,
      );

      await expect(
        routes.connect(other).acceptActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notPendingActiveController);

      await routes.connect(third).acceptActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect((await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).activeController).to.equal(
        third.address,
      );
    });

    it("Should revert initiateActiveControllerTransfer for invalid newActiveController", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, other } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes
          .connect(owner)
          .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, ethers.ZeroAddress),
      ).to.be.revertedWith(XR.invalidActiveController);

      await expect(
        routes
          .connect(owner)
          .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, owner.address),
      ).to.be.revertedWith(XR.sameActiveController);

      await expect(
        routes
          .connect(owner)
          .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, NO_ACTIVE_CONTROLLER),
      ).to.be.revertedWith(XR.useRenounceActiveControl);

      await expect(
        routes
          .connect(other)
          .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, other.address),
      ).to.be.revertedWith(XR.notActiveController);
    });

    it("Should renounce active control and block further toggles", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await expect(routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "ActiveControllerRenounced")
        .and.not.to.emit(routes, "RouteActiveStatusUpdated");

      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(record.isActive).to.equal(true);
      expect(record.activeController).to.equal(NO_ACTIVE_CONTROLLER);
      expect(await routes.NO_ACTIVE_CONTROLLER()).to.equal(NO_ACTIVE_CONTROLLER);

      await expect(
        routes.connect(owner).activateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.activeControlRenounced);

      await expect(
        routes.connect(owner).initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, owner.address),
      ).to.be.revertedWith(XR.activeControlRenounced);
    });

    it("Should keep isActive false when renouncing an inactive route", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      await expect(routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "ActiveControllerRenounced")
        .and.not.to.emit(routes, "RouteActiveStatusUpdated");

      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(record.isActive).to.equal(false);
      expect(record.activeController).to.equal(NO_ACTIVE_CONTROLLER);
    });

    it("Should clear pending transfer on renounce", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, other } = fixture;
      await createDefaultRoute(fixture);

      await routes
        .connect(owner)
        .initiateActiveControllerTransfer(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, other.address);
      await routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      expect(await routes.pendingActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.equal(
        ethers.ZeroAddress,
      );
      await expect(
        routes.connect(other).acceptActiveController(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.activeControlRenounced);
    });

    it("Should revert renounceActiveControl when already renounced", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      await expect(
        routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.activeControlRenounced);
    });

    it("Should still resolve via resolveRouteIfActive when renounced while active", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).renounceActiveControl(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      expect(await routes.resolveRouteIfActive(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.deep.equal([
        buildTarget,
        RT0,
      ]);
    });
  });

  describe("freezeRouteBook", function () {
    it("Should set routeBookFrozen and emit RouteBookFrozen", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(routes.connect(owner).freezeRouteBook(XNS_NAME)).to.emit(
        routes,
        "RouteBookFrozen",
      );

      expect(await routes.isRouteBookFrozen(XNS_NAME)).to.equal(true);
    });

    it("Should block createRoute but allow deactivateRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, "new-one", buildTarget, RT0),
      ).to.be.revertedWith(XR.routeBookFrozen);

      await expect(routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
    });

    it("Should not emit RouteBookFrozen on second call", async function () {
      const { routes, owner } = await loadFixture(deployFixture);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      const filter = routes.filters.RouteBookFrozen();
      const before = (await routes.queryFilter(filter)).length;
      await routes.connect(owner).freezeRouteBook(XNS_NAME);
      const after = (await routes.queryFilter(filter)).length;
      expect(after).to.equal(before);
    });

    it("Should revert with NotXnsNameOwner", async function () {
      const { routes, other } = await loadFixture(deployFixture);

      await expect(routes.connect(other).freezeRouteBook(XNS_NAME)).to.be.revertedWith(
        XR.notXnsNameOwner,
      );
    });
  });

  describe("getRouteRecord", function () {
    it("Should return empty record when route is missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      const record = await routes.getRouteRecord(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(isLiveTarget(record.target)).to.equal(false);
      expect(record.target).to.equal(ethers.ZeroAddress);
    });

    it("Should revert getRouteRecord with InvalidRouteLabel for colon in label when scope is empty", async function () {
      const { routes } = await loadFixture(deployFixture);
      const aliasRoute = `${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      await expect(routes.getRouteRecord(XNS_NAME, "", aliasRoute)).to.be.revertedWith(
        XR.invalidRouteLabel,
      );
    });

    it("Should return getRouteRecord for an existing route string", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const fullPath = `${XNS_NAME}/${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      const record = await getRouteRecordByRoute(routes, fullPath);

      expect(record.target).to.equal(buildTarget);
      expect(record.isActive).to.equal(true);
      expect(record.routeType).to.equal(RT0);
      expect(record.activeController).to.equal(owner.address);
    });

    it("Should revert getRouteRecord with InvalidRoute when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(getRouteRecordByRoute(routes, `${ROUTE_SCOPE}:${ROUTE_LABEL}`)).to.be.revertedWith(
        XR.invalidRoute,
      );
    });

    it("Should return empty record for missing route string", async function () {
      const { routes } = await loadFixture(deployFixture);
      const fullPath = `${XNS_NAME}/${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      const record = await getRouteRecordByRoute(routes, fullPath);
      expect(record.target).to.equal(ethers.ZeroAddress);
    });
  });

  describe("resolveRoute and resolveRouteIfActive", function () {
    it("Should resolve an active route by tuple via resolveRouteIfActive", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const [target, routeType] = await routes.resolveRouteIfActive(
        XNS_NAME,
        ROUTE_SCOPE,
        ROUTE_LABEL,
      );
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should resolve an active route by route string via resolveRouteIfActive", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const fullPath = `${XNS_NAME}/${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      const [target, routeType] = await resolveRouteIfActiveByRoute(routes, fullPath);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should resolve an inactive route by tuple via resolveRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      const [target, routeType] = await routes.resolveRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should resolve an inactive route by route string via resolveRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      const fullPath = `${XNS_NAME}/${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      const [target, routeType] = await resolveRouteByRoute(routes, fullPath);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should revert resolveRouteIfActive when route is missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      await expect(
        routes.resolveRouteIfActive(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.routeNotFound);
    });

    it("Should revert resolveRoute when route is missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      await expect(
        routes.resolveRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.routeNotFound);
    });

    it("Should revert resolveRouteIfActive when route is inactive", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      await expect(
        routes.resolveRouteIfActive(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.routeInactive);
    });

    it("Should resolve via resolveRoute when route book is frozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRouteBook(XNS_NAME);

      expect(await routes.isRouteBookFrozen(XNS_NAME)).to.equal(true);

      const [target, routeType] = await routes.resolveRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should revert resolveRouteIfActive with InvalidRoute when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(
        resolveRouteIfActiveByRoute(routes, `${ROUTE_SCOPE}:${ROUTE_LABEL}`),
      ).to.be.revertedWith(XR.invalidRoute);
    });

    it("Should revert resolveRoute with InvalidRoute when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(
        resolveRouteByRoute(routes, `${ROUTE_SCOPE}:${ROUTE_LABEL}`),
      ).to.be.revertedWith(XR.invalidRoute);
    });
  });

  describe("route key list", function () {
    it("Should start with zero keys for a name", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await routes.getRouteKeyCount(XNS_NAME)).to.equal(0n);
      const keys = await routes.getRouteKeys(XNS_NAME, 0, 0);
      expect(keys.length).to.equal(0);
    });

    it("Should add one key on createRoute and expose it via slice and getRouteRecord", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const rk = routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);

      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      expect(await routes.getRouteKeyCount(XNS_NAME)).to.equal(1n);
      const keys = await routes.getRouteKeys(XNS_NAME, 0, 1);
      expect(keys.length).to.equal(1);
      expect(keys[0]).to.equal(rk);

      const [target, routeType, isActive, activeController] = await getRouteRecordSingle(
        routes,
        rk,
      );
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
      expect(isActive).to.equal(true);
      expect(activeController).to.equal(owner.address);
    });

    it("Should not add a key when createRoute reverts with RouteAlreadyExists", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);

      expect(await routes.getRouteKeyCount(XNS_NAME)).to.equal(1n);
    });

    it("Should return partial slices of getRouteKeys", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, "other-route", buildTarget, RT0);

      const k0 = routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      const k1 = routeStorageKey(XNS_NAME, ROUTE_SCOPE, "other-route");

      const mid = await routes.getRouteKeys(XNS_NAME, 1, 2);
      expect(mid.length).to.equal(1);
      expect(mid[0]).to.equal(k1);

      const emptyWhenStartEqualsEnd = await routes.getRouteKeys(XNS_NAME, 1, 1);
      expect(emptyWhenStartEqualsEnd.length).to.equal(0);

      const all = await routes.getRouteKeys(XNS_NAME, 0, 2);
      expect(all[0]).to.equal(k0);
      expect(all[1]).to.equal(k1);
    });

    it("Should read multiple keys via getRouteRecord in a loop", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);
      await routes
        .connect(owner)
        .createRouteWithController(
          XNS_NAME,
          ROUTE_SCOPE,
          "other-route",
          buildTarget,
          RT0,
          other.address,
        );
      await routes.connect(other).deactivateRoute(XNS_NAME, ROUTE_SCOPE, "other-route");

      const k0 = routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      const k1 = routeStorageKey(XNS_NAME, ROUTE_SCOPE, "other-route");
      const kAbsent = ethers.keccak256(ethers.toUtf8Bytes("no-such-route-key"));

      const r0 = await getRouteRecordByKey(routes, k0);
      const r1 = await getRouteRecordByKey(routes, k1);
      const rAbsent = await getRouteRecordByKey(routes, kAbsent);

      expect(r0.target).to.equal(buildTarget);
      expect(r0.routeType).to.equal(RT0);
      expect(r0.isActive).to.equal(true);
      expect(r0.activeController).to.equal(owner.address);
      expect(r1.target).to.equal(buildTarget);
      expect(r1.isActive).to.equal(false);
      expect(r1.activeController).to.equal(other.address);
      expect(rAbsent.target).to.equal(ethers.ZeroAddress);
    });

    it("Should revert getRouteKeys only when start > end; past-range start returns empty", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(routes.getRouteKeys(XNS_NAME, 1, 0)).to.be.revertedWith(XR.invalidRouteKeySlice);

      const pastRange = await routes.getRouteKeys(XNS_NAME, 2, 3);
      expect(pastRange.length).to.equal(0);
    });

    it("Should clamp end to log length when end exceeds length", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const k0 = routeStorageKey(XNS_NAME, ROUTE_SCOPE, ROUTE_LABEL);
      const clamped = await routes.getRouteKeys(XNS_NAME, 0, 999);
      const explicit = await routes.getRouteKeys(XNS_NAME, 0, 1);
      expect(clamped.length).to.equal(1);
      expect(clamped[0]).to.equal(k0);
      expect(clamped.length).to.equal(explicit.length);
      expect(clamped[0]).to.equal(explicit[0]);

      const maxEnd = (1n << 256n) - 1n;
      const allViaMax = await routes.getRouteKeys(XNS_NAME, 0, maxEnd);
      expect(allViaMax.length).to.equal(1);
      expect(allViaMax[0]).to.equal(k0);
    });
  });

  describe("route segment validation (pure views)", function () {
    it("Should expose isValidRouteScope consistent with mutators", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await routes.isValidRouteScope("")).to.equal(true);
      expect(await routes.isValidRouteScope(ROUTE_SCOPE)).to.equal(true);
      expect(await routes.isValidRouteScope("a".repeat(21))).to.equal(false);
      expect(await routes.isValidRouteScope("Bad")).to.equal(false);
    });

    it("Should expose isValidRouteLabel consistent with mutators", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await routes.isValidRouteLabel("")).to.equal(false);
      expect(await routes.isValidRouteLabel(ROUTE_LABEL)).to.equal(true);
      expect(await routes.isValidRouteLabel("a".repeat(33))).to.equal(false);
    });

    it("Should expose isValidRouteScopeAndLabel as conjunction", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await routes.isValidRouteScopeAndLabel("", ROUTE_LABEL)).to.equal(true);
      expect(await routes.isValidRouteScopeAndLabel(ROUTE_SCOPE, ROUTE_LABEL)).to.equal(true);
      expect(await routes.isValidRouteScopeAndLabel("bad!", ROUTE_LABEL)).to.equal(false);
      expect(await routes.isValidRouteScopeAndLabel(ROUTE_SCOPE, "")).to.equal(false);
    });
  });

  describe("bare XNS name canonicalization", function () {
    const BARE_LABEL = "barecanon";
    const BARE_CANON = "barecanon.x";

    async function deployWithBare(): Promise<Fixture> {
      const f = await deployFixture();
      await f.mockXns.setResolution(BARE_CANON, f.owner.address);
      return f;
    }

    it("Should resolve routes created with bare label when queried with canonical name", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployWithBare);
      const r = "my-route";
      await routes.connect(owner).createRoute(BARE_LABEL, "", r, buildTarget, RT0);

      expect(isLiveTarget((await routes.getRouteRecord(BARE_CANON, "", r)).target)).to.equal(true);
      expect((await routes.getRouteRecord(BARE_CANON, "", r)).target).to.equal(buildTarget);
    });

    it("Should treat bare and canonical name as the same route book (second create reverts)", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployWithBare);
      const r = "my-route";
      await routes.connect(owner).createRoute(BARE_LABEL, "", r, buildTarget, RT0);

      await expect(
        routes.connect(owner).createRoute(BARE_CANON, "", r, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);
    });

    it("Should emit canonicalXNSName in RouteActiveStatusUpdated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployWithBare);
      await routes.connect(owner).createRoute(BARE_LABEL, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      await expect(routes.connect(owner).deactivateRoute(BARE_CANON, ROUTE_SCOPE, ROUTE_LABEL))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(
          xnsNameKey(BARE_LABEL),
          routeStorageKey(BARE_LABEL, ROUTE_SCOPE, ROUTE_LABEL),
          BARE_CANON,
          ROUTE_SCOPE,
          ROUTE_LABEL,
          false,
        );
    });

    it("Should resolve getRouteRecord when the path uses a bare first segment", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployWithBare);
      await routes.connect(owner).createRoute(BARE_LABEL, ROUTE_SCOPE, ROUTE_LABEL, buildTarget, RT0);

      const fullPath = `${BARE_LABEL}/${ROUTE_SCOPE}:${ROUTE_LABEL}`;
      const record = await getRouteRecordByRoute(routes, fullPath);
      expect(record.target).to.equal(buildTarget);
    });
  });
});
