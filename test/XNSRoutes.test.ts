import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import type { MockXNS, XNSRoutes } from "../typechain-types";

describe("XNSRoutes", function () {
  const { ethers } = hre;

  const LABEL = "xns";
  const NAMESPACE = "action";
  const ROUTE_LABEL = "register-name";
  const OTHER_LABEL = "other";
  const OTHER_NAMESPACE = "action";
  const XNS_NAME = `${LABEL}@${NAMESPACE}`;
  /** Default `routeType` in tests; semantics are offchain */
  const RT0 = 0;
  /** Empty `bytes` — missing-route sentinel (`target.length == 0`). */
  const EMPTY_TARGET = "0x";

  /** Matches `require(..., "XNSRoutes: ...")` in `XNSRoutes.sol`. */
  const XR = {
    zeroXnsAddress: "XNSRoutes: 0x XNS address",
    invalidXnsName: "XNSRoutes: invalid XNS name",
    invalidRouteLabel: "XNSRoutes: invalid route label",
    invalidTarget: "XNSRoutes: invalid target",
    notXnsNameOwner: "XNSRoutes: not XNS name owner",
    routeNotFound: "XNSRoutes: route not found",
    routeInactive: "XNSRoutes: route inactive",
    routeNotFrozen: "XNSRoutes: route not frozen",
    routeBookClosed: "XNSRoutes: route book closed",
    routeFrozen: "XNSRoutes: route frozen",
    routeAlreadyExists: "XNSRoutes: route already exists",
    invalidRoute: "XNSRoutes: invalid route",
    invalidSlice: "XNSRoutes: invalid slice",
  } as const;

  function formatRoute(label: string, namespace: string, routeLabel: string): string {
    return `${label}@${namespace}/${routeLabel}`;
  }

  /** `keccak256(target)` as emitted in `RouteCreated` / `RouteUpdated`. */
  function hashTarget(target: string): string {
    return ethers.keccak256(target);
  }

  /** Matches `XNSRoutes._xnsNameKey`: `keccak256(abi.encodePacked(label, "@", namespace))`. */
  function xnsNameKey(label: string, namespace: string): string {
    return ethers.solidityPackedKeccak256(["string", "string", "string"], [label, "@", namespace]);
  }

  /** Matches `XNSRoutes._routeKey`: `keccak256(abi.encodePacked(label, "@", namespace, "/", routeLabel))`. */
  function routeStorageKey(label: string, namespace: string, routeLabel: string): string {
    return ethers.solidityPackedKeccak256(
      ["string", "string", "string", "string", "string"],
      [label, "@", namespace, "/", routeLabel],
    );
  }

  /** Disambiguate ethers overload: `getAddress(label, namespace)`. */
  async function getXnsAddress(mockXns: MockXNS, label: string, namespace: string) {
    return mockXns["getAddress(string,string)"](label, namespace);
  }

  /** Disambiguate ethers overload: `closeRouteBook(label, namespace)`. */
  async function closeRouteBookTuple(routes: XNSRoutes, label: string, namespace: string) {
    return routes["closeRouteBook(string,string)"](label, namespace);
  }

  /** Disambiguate ethers overload: `isRouteBookClosed(label, namespace)`. */
  async function isRouteBookClosedTuple(routes: XNSRoutes, label: string, namespace: string) {
    return routes["isRouteBookClosed(string,string)"](label, namespace);
  }

  /** Disambiguate ethers overload: `getRouteKeyCount(label, namespace)`. */
  async function getRouteKeyCountTuple(routes: XNSRoutes, label: string, namespace: string) {
    return routes["getRouteKeyCount(string,string)"](label, namespace);
  }

  /** Disambiguate ethers overload: `getRouteKeys(label, namespace, start, end)`. */
  async function getRouteKeysTuple(
    routes: XNSRoutes,
    label: string,
    namespace: string,
    start: number | bigint,
    end: number | bigint,
  ) {
    return routes["getRouteKeys(string,string,uint256,uint256)"](label, namespace, start, end);
  }

  /** Disambiguate ethers overload: `getRouteEntries(label, namespace, start, end)`. */
  async function getRouteEntriesTuple(
    routes: XNSRoutes,
    label: string,
    namespace: string,
    start: number | bigint,
    end: number | bigint,
  ) {
    return routes["getRouteEntries(string,string,uint256,uint256)"](label, namespace, start, end);
  }

  /** Disambiguate ethers overload: `getRouteRecord(bytes32)`. */
  async function getRouteRecordByKey(routes: XNSRoutes, routeKey: string) {
    return routes["getRouteRecord(bytes32)"](routeKey);
  }

  /** Disambiguate ethers overload: `getRouteRecord(string)` (route). */
  async function getRouteRecordByRoute(routes: XNSRoutes, route: string) {
    return routes["getRouteRecord(string)"](route);
  }

  /** Disambiguate ethers overload: `resolveRoute(label, namespace, routeLabel)`. */
  async function resolveRouteTuple(
    routes: XNSRoutes,
    label: string,
    namespace: string,
    routeLabel: string,
  ) {
    return routes["resolveRoute(string,string,string)"](label, namespace, routeLabel);
  }

  /** Disambiguate ethers overload: `resolveRoute(string)` (route). */
  async function resolveRouteByRoute(routes: XNSRoutes, route: string) {
    return routes["resolveRoute(string)"](route);
  }

  /** 20-byte EVM-address payload as hex (ABI `bytes`). */
  function addressTarget(addr: string): string {
    return ethers.hexlify(ethers.getBytes(addr));
  }

  interface Fixture {
    routes: XNSRoutes;
    mockXns: MockXNS;
    contractOwner: SignerWithAddress;
    owner: SignerWithAddress;
    other: SignerWithAddress;
    buildTarget: string;
  }

  async function deployFixture(): Promise<Fixture> {
    const [contractOwner, owner, other] = await ethers.getSigners();
    const mockXns = await ethers.deployContract("MockXNS");
    await mockXns.waitForDeployment();
    const mockAddr = String(mockXns.target);
    const routes = await ethers.deployContract("XNSRoutes", [contractOwner.address, mockAddr], {
      value: 0n,
    });
    await routes.waitForDeployment();

    await mockXns.setResolution(LABEL, NAMESPACE, owner.address);
    await mockXns.setResolution(OTHER_LABEL, OTHER_NAMESPACE, other.address);

    const buildTarget = addressTarget(ethers.Wallet.createRandom().address);

    return {
      routes,
      mockXns,
      contractOwner,
      owner,
      other,
      buildTarget,
    };
  }

  async function createDefaultRoute(fixture: Fixture) {
    const { routes, owner, buildTarget } = fixture;
    await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
  }

  describe("constructor", function () {
    it("Should set the provided initial owner", async function () {
      const { routes, contractOwner } = await loadFixture(deployFixture);
      expect(await routes.owner()).to.equal(contractOwner.address);
    });

    it("Should store the XNS registry and expose it via XNS()", async function () {
      const { routes, mockXns } = await loadFixture(deployFixture);
      expect(await routes.XNS()).to.equal(String(mockXns.target));
    });

    it("Should revert when initialOwner is the zero address", async function () {
      const mockXns = await ethers.deployContract("MockXNS");
      const XNSRoutes = await ethers.getContractFactory("XNSRoutes");

      await expect(XNSRoutes.deploy(ethers.ZeroAddress, String(mockXns.target), { value: 0n }))
        .to.be.revertedWithCustomError(XNSRoutes, "OwnableInvalidOwner")
        .withArgs(ethers.ZeroAddress);
    });

    it("Should revert with zero XNS address when xnsContract is zero address", async function () {
      const [contractOwner] = await ethers.getSigners();
      const XNSRoutes = await ethers.getContractFactory("XNSRoutes");
      await expect(
        XNSRoutes.deploy(contractOwner.address, ethers.ZeroAddress, { value: 0n }),
      ).to.be.revertedWith(XR.zeroXnsAddress);
    });

    it("Should register routes@xns to the deployed registry via constructor", async function () {
      const { routes, mockXns } = await loadFixture(deployFixture);
      const resolved = await getXnsAddress(mockXns, "routes", "xns");
      expect(resolved).to.equal(String(routes.target));
    });
  });

  describe("contract ownership", function () {
    it("Should transfer ownership using the two-step flow", async function () {
      const { routes, contractOwner, other } = await loadFixture(deployFixture);

      await routes.connect(contractOwner).transferOwnership(other.address);
      expect(await routes.owner()).to.equal(contractOwner.address);
      expect(await routes.pendingOwner()).to.equal(other.address);

      await routes.connect(other).acceptOwnership();
      expect(await routes.owner()).to.equal(other.address);
      expect(await routes.pendingOwner()).to.equal(ethers.ZeroAddress);
    });

    it("Should not grant the contract owner authority over another owner's routes", async function () {
      const { routes, contractOwner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(contractOwner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });
  });

  describe("createRoute", function () {
    it("Should let the name owner create a route and emit RouteCreated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      )
        .to.emit(routes, "RouteCreated")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          hashTarget(buildTarget),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
          RT0,
        );

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL);
      expect(record.target).to.equal(buildTarget);
      expect(record.isActive).to.equal(true);
      expect(record.isFrozen).to.equal(false);
      expect(record.routeType).to.equal(RT0);
    });

    it("Should revert with NotXnsNameOwner when caller is not XNS owner", async function () {
      const { routes, other, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(other).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should revert with NotXnsNameOwner when XNS resolves owner to zero", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute("orphan", "test", ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should allow route length up to 32 chars and reject >32", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const route32 = "a".repeat(32);
      const route33 = "a".repeat(33);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, route32, buildTarget, RT0),
      ).to.emit(routes, "RouteCreated");

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, route33, buildTarget, RT0),
      ).to.be.revertedWith(XR.invalidRouteLabel);
    });

    it("Should revert with InvalidTarget when target is empty", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, EMPTY_TARGET, RT0),
      ).to.be.revertedWith(XR.invalidTarget);
    });

    it("Should accept a target longer than 256 bytes", async function () {
      const { routes, owner } = await loadFixture(deployFixture);
      const longTarget = ethers.hexlify(new Uint8Array(512).fill(0xab));

      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, longTarget, RT0);

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).target).to.equal(
        longTarget,
      );
    });

    it("Should revert with RouteBookClosed after closeRouteBook", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeBookClosed);
    });

    it("Should keep routes independent per label, namespace, and routeLabel", async function () {
      const { routes, mockXns, owner, other, buildTarget } = await loadFixture(deployFixture);
      const t1 = buildTarget;
      const t2 = addressTarget(other.address);

      await mockXns.setResolution(LABEL, "pay", owner.address);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, t1, RT0);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", t2, RT0);
      await routes.connect(owner).createRoute(LABEL, "pay", ROUTE_LABEL, t2, RT0);
      await routes.connect(other).createRoute(OTHER_LABEL, OTHER_NAMESPACE, ROUTE_LABEL, t2, RT0);

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).target).to.equal(t1);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, "other-route")).target).to.equal(t2);
      expect((await routes.getRouteRecord(LABEL, "pay", ROUTE_LABEL)).target).to.equal(t2);
      expect(
        (await routes.getRouteRecord(OTHER_LABEL, OTHER_NAMESPACE, ROUTE_LABEL)).target,
      ).to.equal(t2);
    });

    it("Should revert with RouteAlreadyExists when createRoute is called twice for same key", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);
    });
  });

  describe("activateRoute and deactivateRoute", function () {
    it("Should deactivate, emit RouteActiveStatusUpdated, and set isActive false", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
          false,
        );

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(false);
    });

    it("Should activate after deactivate and emit RouteActiveStatusUpdated", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      await expect(routes.connect(owner).activateRoute(LABEL, NAMESPACE, ROUTE_LABEL))
        .to.emit(routes, "RouteActiveStatusUpdated")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
          true,
        );

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(true);
    });

    it("Should not emit RouteActiveStatusUpdated when deactivate called twice", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      await expect(
        routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.not.emit(routes, "RouteActiveStatusUpdated");
    });

    it("Should not emit RouteActiveStatusUpdated when activate called while already active", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(routes.connect(owner).activateRoute(LABEL, NAMESPACE, ROUTE_LABEL)).to.not.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
    });

    it("Should succeed after route book close", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      await expect(routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(false);
    });

    it("Should revert with NotXnsNameOwner when caller is not XNS owner", async function () {
      const { routes, owner, other, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(other).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notXnsNameOwner);
      await expect(
        routes.connect(other).activateRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should let the XNS name owner toggle isActive", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(false);

      await routes.connect(owner).activateRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(true);
    });

    it("Should revert with RouteNotFound when route missing", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, "missing"),
      ).to.be.revertedWith(XR.routeNotFound);
    });
  });

  describe("updateRoute", function () {
    it("Should let the name owner update target and routeType and emit RouteUpdated", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      const updatedTarget = addressTarget("0x00000000000000000000000000000000000000AA");
      const newType = 2;

      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, updatedTarget, newType),
      )
        .to.emit(routes, "RouteUpdated")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          hashTarget(updatedTarget),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
          newType,
        );

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL);
      expect(record.target).to.equal(updatedTarget);
      expect(record.routeType).to.equal(newType);
      expect(record.isActive).to.equal(true);
      expect(record.isFrozen).to.equal(false);
    });

    it("Should not emit RouteUpdated when values are unchanged", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.not.emit(routes, "RouteUpdated");
    });

    it("Should revert when caller is not the XNS name owner", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, other, buildTarget } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(other).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, 1),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should revert with RouteNotFound when route does not exist", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeNotFound);
    });

    it("Should revert with InvalidTarget when newTarget is empty", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, EMPTY_TARGET, RT0),
      ).to.be.revertedWith(XR.invalidTarget);
    });

    it("Should accept a newTarget longer than 256 bytes", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);
      const longTarget = ethers.hexlify(new Uint8Array(512).fill(0xcd));

      await routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, longTarget, RT0);

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).target).to.equal(
        longTarget,
      );
    });

    it("Should revert with RouteFrozen after freezeRoute", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, 1),
      ).to.be.revertedWith(XR.routeFrozen);
    });

    it("Should still allow updateRoute after closeRouteBook", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget, other } = fixture;
      await createDefaultRoute(fixture);
      const newTarget = addressTarget(other.address);

      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      await expect(routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, newTarget, 1))
        .to.emit(routes, "RouteUpdated")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          hashTarget(newTarget),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
          1,
        );

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL);
      expect(record.target).to.equal(newTarget);
      expect(record.routeType).to.equal(1);
      expect(record.isFrozen).to.equal(false);
    });
  });

  describe("freezeRoute", function () {
    it("Should freeze a route and emit RouteFrozen", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await expect(routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL))
        .to.emit(routes, "RouteFrozen")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
        );

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL);
      expect(record.isFrozen).to.equal(true);
    });

    it("Should not emit RouteFrozen when already frozen", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      await expect(routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL)).to.not.emit(
        routes,
        "RouteFrozen",
      );
    });

    it("Should still allow activate/deactivate after freezeRoute", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(false);
      await routes.connect(owner).activateRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isActive).to.equal(true);
    });

    it("Should revert when caller is not the XNS name owner", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, other } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(other).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should revert with RouteNotFound when route does not exist", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(
        routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.routeNotFound);
    });
  });

  describe("batchFreezeRoutes", function () {
    it("Should freeze multiple routes and emit RouteFrozen for each new freeze", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget } = fixture;
      await createDefaultRoute(fixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", buildTarget, RT0);

      await expect(
        routes.connect(owner).batchFreezeRoutes(LABEL, NAMESPACE, [ROUTE_LABEL, "other-route"]),
      )
        .to.emit(routes, "RouteFrozen")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL),
          LABEL,
          NAMESPACE,
          ROUTE_LABEL,
        )
        .and.to.emit(routes, "RouteFrozen")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, "other-route"),
          LABEL,
          NAMESPACE,
          "other-route",
        );

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isFrozen).to.equal(true);
      expect((await routes.getRouteRecord(LABEL, NAMESPACE, "other-route")).isFrozen).to.equal(
        true,
      );
    });

    it("Should skip already-frozen routes without emitting for them", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner, buildTarget } = fixture;
      await createDefaultRoute(fixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      await expect(
        routes.connect(owner).batchFreezeRoutes(LABEL, NAMESPACE, [ROUTE_LABEL, "other-route"]),
      )
        .to.emit(routes, "RouteFrozen")
        .withArgs(
          xnsNameKey(LABEL, NAMESPACE),
          routeStorageKey(LABEL, NAMESPACE, "other-route"),
          LABEL,
          NAMESPACE,
          "other-route",
        );

      const filter = routes.filters.RouteFrozen();
      const logs = await routes.queryFilter(filter);
      // one from freezeRoute + one from batch for other-route
      expect(logs.length).to.equal(2);
    });

    it("Should succeed as a no-op for an empty routeLabels array", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await expect(routes.connect(owner).batchFreezeRoutes(LABEL, NAMESPACE, [])).to.not.emit(
        routes,
        "RouteFrozen",
      );
    });

    it("Should revert when any route is missing", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, owner } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(owner).batchFreezeRoutes(LABEL, NAMESPACE, [ROUTE_LABEL, "missing"]),
      ).to.be.revertedWith(XR.routeNotFound);
    });

    it("Should revert when caller is not the XNS name owner", async function () {
      const fixture = await loadFixture(deployFixture);
      const { routes, other } = fixture;
      await createDefaultRoute(fixture);

      await expect(
        routes.connect(other).batchFreezeRoutes(LABEL, NAMESPACE, [ROUTE_LABEL]),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });
  });

  describe("closeRouteBook", function () {
    it("Should set routeBookClosed and emit RouteBookClosed via tuple overload", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE))
        .to.emit(routes, "RouteBookClosed")
        .withArgs(xnsNameKey(LABEL, NAMESPACE), LABEL, NAMESPACE);

      expect(await isRouteBookClosedTuple(routes, LABEL, NAMESPACE)).to.equal(true);
    });

    it("Should set routeBookClosed and emit RouteBookClosed via xnsName overload", async function () {
      const { routes, owner } = await loadFixture(deployFixture);

      await expect(routes.connect(owner)["closeRouteBook(string)"](XNS_NAME))
        .to.emit(routes, "RouteBookClosed")
        .withArgs(xnsNameKey(LABEL, NAMESPACE), LABEL, NAMESPACE);

      expect(await routes.isRouteBookClosed(XNS_NAME)).to.equal(true);
    });

    it("Should block createRoute but allow updateRoute and deactivateRoute", async function () {
      const { routes, owner, buildTarget, other } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      expect((await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL)).isFrozen).to.equal(false);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, "new-one", buildTarget, RT0),
      ).to.be.revertedWith(XR.routeBookClosed);

      const newTarget = addressTarget(other.address);
      await expect(
        routes.connect(owner).updateRoute(LABEL, NAMESPACE, ROUTE_LABEL, newTarget, 1),
      ).to.emit(routes, "RouteUpdated");

      await expect(routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL)).to.emit(
        routes,
        "RouteActiveStatusUpdated",
      );
    });

    it("Should not emit RouteBookClosed on second call", async function () {
      const { routes, owner } = await loadFixture(deployFixture);
      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      await expect(closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE)).to.not.emit(
        routes,
        "RouteBookClosed",
      );
    });

    it("Should revert with NotXnsNameOwner", async function () {
      const { routes, other } = await loadFixture(deployFixture);

      await expect(closeRouteBookTuple(routes.connect(other), LABEL, NAMESPACE)).to.be.revertedWith(
        XR.notXnsNameOwner,
      );
    });
  });

  describe("getRouteRecord", function () {
    it("Should return empty record when route is missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, ROUTE_LABEL);
      expect(record.target).to.equal(EMPTY_TARGET);
    });

    it("Should return getRouteRecord for an existing route string", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      const fullPath = formatRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      const record = await getRouteRecordByRoute(routes, fullPath);

      expect(record.target).to.equal(buildTarget);
      expect(record.isActive).to.equal(true);
      expect(record.routeType).to.equal(RT0);
    });

    it("Should revert getRouteRecord with InvalidRoute when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(getRouteRecordByRoute(routes, XNS_NAME)).to.be.revertedWith(XR.invalidRoute);
    });

    it("Should return empty record for missing route string", async function () {
      const { routes } = await loadFixture(deployFixture);
      const fullPath = formatRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      const record = await getRouteRecordByRoute(routes, fullPath);
      expect(record.target).to.equal(EMPTY_TARGET);
    });
  });

  describe("resolveRoute", function () {
    it("Should resolve a frozen active route by tuple", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      const [target, routeType] = await resolveRouteTuple(routes, LABEL, NAMESPACE, ROUTE_LABEL);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should resolve a frozen active route by route string", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      const fullPath = formatRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      const [target, routeType] = await resolveRouteByRoute(routes, fullPath);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should revert when route is not frozen", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(resolveRouteTuple(routes, LABEL, NAMESPACE, ROUTE_LABEL)).to.be.revertedWith(
        XR.routeNotFrozen,
      );
    });

    it("Should revert when frozen route is inactive", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      await expect(resolveRouteTuple(routes, LABEL, NAMESPACE, ROUTE_LABEL)).to.be.revertedWith(
        XR.routeInactive,
      );
    });

    it("Should revert when route is missing", async function () {
      const { routes } = await loadFixture(deployFixture);

      await expect(resolveRouteTuple(routes, LABEL, NAMESPACE, ROUTE_LABEL)).to.be.revertedWith(
        XR.routeNotFound,
      );
    });

    it("Should reject extra path segments", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      const extraPath = `${formatRoute(LABEL, NAMESPACE, ROUTE_LABEL)}/extra/path`;
      await expect(resolveRouteByRoute(routes, extraPath)).to.be.revertedWith(XR.invalidRoute);
    });

    it("Should not strip query parameters automatically", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      const parametrized = `${formatRoute(LABEL, NAMESPACE, ROUTE_LABEL)}?amount=10&to=0xabc`;
      await expect(resolveRouteByRoute(routes, parametrized)).to.be.revertedWith(XR.routeNotFound);
    });

    it("Should resolve via resolveRoute when route book is closed", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).freezeRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      await closeRouteBookTuple(routes.connect(owner), LABEL, NAMESPACE);

      expect(await isRouteBookClosedTuple(routes, LABEL, NAMESPACE)).to.equal(true);

      const [target, routeType] = await resolveRouteTuple(routes, LABEL, NAMESPACE, ROUTE_LABEL);
      expect(target).to.equal(buildTarget);
      expect(routeType).to.equal(RT0);
    });

    it("Should revert resolveRoute with InvalidRoute when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(resolveRouteByRoute(routes, XNS_NAME)).to.be.revertedWith(XR.invalidRoute);
    });
  });

  describe("splitRoute", function () {
    it("Should parse a complete route", async function () {
      const { routes } = await loadFixture(deployFixture);
      const [label, namespace, routeLabel] = await routes.splitRoute(
        formatRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      );
      expect(label).to.equal(LABEL);
      expect(namespace).to.equal(NAMESPACE);
      expect(routeLabel).to.equal(ROUTE_LABEL);
    });

    it("Should revert when extra path segments are present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(
        routes.splitRoute(`${formatRoute(LABEL, NAMESPACE, ROUTE_LABEL)}/extra/path`),
      ).to.be.revertedWith(XR.invalidRoute);
    });

    it("Should revert when no slash is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitRoute(XNS_NAME)).to.be.revertedWith(XR.invalidRoute);
    });

    const invalidRoutes: [string, string][] = [
      ["", XR.invalidRoute],
      [`/${ROUTE_LABEL}`, XR.invalidRoute],
      [`${XNS_NAME}/`, XR.invalidRoute],
      [`${LABEL}${NAMESPACE}/${ROUTE_LABEL}`, XR.invalidXnsName],
      [`${LABEL}@${NAMESPACE}@extra/${ROUTE_LABEL}`, XR.invalidXnsName],
    ];

    for (const [input, error] of invalidRoutes) {
      it(`Should revert for malformed route "${input}"`, async function () {
        const { routes } = await loadFixture(deployFixture);
        await expect(routes.splitRoute(input)).to.be.revertedWith(error);
      });
    }

    it("Should not strip a query suffix from the route label", async function () {
      const { routes } = await loadFixture(deployFixture);
      const [label, namespace, routeLabel] = await routes.splitRoute(
        `${formatRoute(LABEL, NAMESPACE, ROUTE_LABEL)}?extra`,
      );
      expect(label).to.equal(LABEL);
      expect(namespace).to.equal(NAMESPACE);
      expect(routeLabel).to.equal(`${ROUTE_LABEL}?extra`);
    });
  });

  describe("splitXNSName", function () {
    it("Should parse label@namespace", async function () {
      const { routes } = await loadFixture(deployFixture);
      const [label, namespace] = await routes.splitXNSName(XNS_NAME);
      expect(label).to.equal(LABEL);
      expect(namespace).to.equal(NAMESPACE);
    });

    it("Should revert when @ is missing", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitXNSName("invalidname")).to.be.revertedWith(XR.invalidXnsName);
    });

    it("Should revert when label is empty", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitXNSName("@action")).to.be.revertedWith(XR.invalidXnsName);
    });

    it("Should revert when namespace is empty", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitXNSName("xns@")).to.be.revertedWith(XR.invalidXnsName);
    });

    it("Should revert when input is empty", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitXNSName("")).to.be.revertedWith(XR.invalidXnsName);
    });

    it("Should revert when @ appears more than once", async function () {
      const { routes } = await loadFixture(deployFixture);
      await expect(routes.splitXNSName("a@b@c")).to.be.revertedWith(XR.invalidXnsName);
    });
  });

  describe("getRouteKey", function () {
    it("Should match the off-chain route key helper for tuple input", async function () {
      const { routes } = await loadFixture(deployFixture);
      const expected = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);

      expect(await routes.getRouteKey(LABEL, NAMESPACE, ROUTE_LABEL)).to.equal(expected);
    });

    it("Should match the off-chain route key helper for a complete route string", async function () {
      const { routes } = await loadFixture(deployFixture);
      const fullPath = formatRoute(LABEL, NAMESPACE, ROUTE_LABEL);
      const expected = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);

      expect(await routes["getRouteKey(string)"](fullPath)).to.equal(expected);
    });

    it("Should agree between tuple and string overloads", async function () {
      const { routes } = await loadFixture(deployFixture);
      const fullPath = formatRoute(LABEL, NAMESPACE, ROUTE_LABEL);

      const fromTuple = await routes.getRouteKey(LABEL, NAMESPACE, ROUTE_LABEL);
      const fromString = await routes["getRouteKey(string)"](fullPath);
      expect(fromString).to.equal(fromTuple);
    });

    it("Should revert the string overload when an extra path segment is present", async function () {
      const { routes } = await loadFixture(deployFixture);
      const extraPath = `${formatRoute(LABEL, NAMESPACE, ROUTE_LABEL)}/extra`;

      await expect(routes["getRouteKey(string)"](extraPath)).to.be.revertedWith(XR.invalidRoute);
    });
  });

  describe("getXNSNameKey", function () {
    it("Should match the off-chain XNS name key helper for tuple input", async function () {
      const { routes } = await loadFixture(deployFixture);
      const expected = xnsNameKey(LABEL, NAMESPACE);

      expect(await routes["getXNSNameKey(string,string)"](LABEL, NAMESPACE)).to.equal(expected);
    });

    it("Should match the off-chain XNS name key helper for a complete XNS name", async function () {
      const { routes } = await loadFixture(deployFixture);
      const expected = xnsNameKey(LABEL, NAMESPACE);

      expect(await routes["getXNSNameKey(string)"](XNS_NAME)).to.equal(expected);
    });

    it("Should agree between tuple and string overloads", async function () {
      const { routes } = await loadFixture(deployFixture);

      const fromTuple = await routes["getXNSNameKey(string,string)"](LABEL, NAMESPACE);
      const fromString = await routes["getXNSNameKey(string)"](XNS_NAME);
      expect(fromString).to.equal(fromTuple);
    });

    it("Should revert the string overload for a malformed XNS name", async function () {
      const { routes } = await loadFixture(deployFixture);

      await expect(routes["getXNSNameKey(string)"]("invalidname")).to.be.revertedWith(
        XR.invalidXnsName,
      );
    });
  });

  describe("route key list", function () {
    it("Should start with zero keys for a name", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await getRouteKeyCountTuple(routes, LABEL, NAMESPACE)).to.equal(0n);
      const keys = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, 0);
      expect(keys.length).to.equal(0);
    });

    it("Should add one key on createRoute and expose it via slice and getRouteRecord", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const rk = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);

      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      expect(await getRouteKeyCountTuple(routes, LABEL, NAMESPACE)).to.equal(1n);
      const keys = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, 1);
      expect(keys.length).to.equal(1);
      expect(keys[0]).to.equal(rk);

      const record = await getRouteRecordByKey(routes, rk);
      expect(record.target).to.equal(buildTarget);
      expect(record.routeType).to.equal(RT0);
      expect(record.isActive).to.equal(true);
      expect(record.isFrozen).to.equal(false);
      expect(record.routeLabel).to.equal(ROUTE_LABEL);
    });

    it("Should not add a key when createRoute reverts with RouteAlreadyExists", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(
        routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);

      expect(await getRouteKeyCountTuple(routes, LABEL, NAMESPACE)).to.equal(1n);
    });

    it("Should return partial slices of getRouteKeys", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", buildTarget, RT0);

      const k0 = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);
      const k1 = routeStorageKey(LABEL, NAMESPACE, "other-route");

      const mid = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 1, 2);
      expect(mid.length).to.equal(1);
      expect(mid[0]).to.equal(k1);

      const emptyWhenStartEqualsEnd = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 1, 1);
      expect(emptyWhenStartEqualsEnd.length).to.equal(0);

      const all = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, 2);
      expect(all[0]).to.equal(k0);
      expect(all[1]).to.equal(k1);
    });

    it("Should read multiple keys via getRouteRecord in a loop", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", buildTarget, RT0);
      await routes.connect(owner).deactivateRoute(LABEL, NAMESPACE, "other-route");

      const k0 = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);
      const k1 = routeStorageKey(LABEL, NAMESPACE, "other-route");
      const kAbsent = ethers.keccak256(ethers.toUtf8Bytes("no-such-route-key"));

      const r0 = await getRouteRecordByKey(routes, k0);
      const r1 = await getRouteRecordByKey(routes, k1);
      const rAbsent = await getRouteRecordByKey(routes, kAbsent);

      expect(r0.target).to.equal(buildTarget);
      expect(r0.routeType).to.equal(RT0);
      expect(r0.isActive).to.equal(true);
      expect(r0.routeLabel).to.equal(ROUTE_LABEL);
      expect(r1.target).to.equal(buildTarget);
      expect(r1.isActive).to.equal(false);
      expect(r1.routeLabel).to.equal("other-route");
      expect(rAbsent.target).to.equal(EMPTY_TARGET);
      expect(rAbsent.routeLabel).to.equal("");
    });

    it("Should store routeLabel on createRoute", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      const globalRoute = "global-route";

      await routes.connect(owner).createRoute(LABEL, NAMESPACE, globalRoute, buildTarget, RT0);

      const record = await routes.getRouteRecord(LABEL, NAMESPACE, globalRoute);
      expect(record.routeLabel).to.equal(globalRoute);
    });

    it("Should return human-readable routes via getRouteEntries", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "global-route", buildTarget, RT0);

      const k0 = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);
      const k1 = routeStorageKey(LABEL, NAMESPACE, "global-route");

      const entries = await getRouteEntriesTuple(routes, LABEL, NAMESPACE, 0, 2);
      expect(entries.length).to.equal(2);
      expect(entries[0].routeKey).to.equal(k0);
      expect(entries[0].record.routeLabel).to.equal(ROUTE_LABEL);
      expect(entries[0].record.target).to.equal(buildTarget);
      expect(entries[1].routeKey).to.equal(k1);
      expect(entries[1].record.routeLabel).to.equal("global-route");
      expect(entries[1].record.isActive).to.equal(true);
    });

    it("Should paginate getRouteEntries with the same rules as getRouteKeys", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, "other-route", buildTarget, RT0);

      const k1 = routeStorageKey(LABEL, NAMESPACE, "other-route");

      const mid = await getRouteEntriesTuple(routes, LABEL, NAMESPACE, 1, 2);
      expect(mid.length).to.equal(1);
      expect(mid[0].routeKey).to.equal(k1);
      expect(mid[0].record.routeLabel).to.equal("other-route");

      await expect(getRouteEntriesTuple(routes, LABEL, NAMESPACE, 1, 0)).to.be.revertedWith(
        XR.invalidSlice,
      );

      const pastRange = await getRouteEntriesTuple(routes, LABEL, NAMESPACE, 2, 3);
      expect(pastRange.length).to.equal(0);
    });

    it("Should revert getRouteKeys only when start > end; past-range start returns empty", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      await expect(getRouteKeysTuple(routes, LABEL, NAMESPACE, 1, 0)).to.be.revertedWith(
        XR.invalidSlice,
      );

      const pastRange = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 2, 3);
      expect(pastRange.length).to.equal(0);
    });

    it("Should clamp end to log length when end exceeds length", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      const k0 = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);
      const clamped = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, 999);
      const explicit = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, 1);
      expect(clamped.length).to.equal(1);
      expect(clamped[0]).to.equal(k0);
      expect(clamped.length).to.equal(explicit.length);
      expect(clamped[0]).to.equal(explicit[0]);

      const maxEnd = (1n << 256n) - 1n;
      const allViaMax = await getRouteKeysTuple(routes, LABEL, NAMESPACE, 0, maxEnd);
      expect(allViaMax.length).to.equal(1);
      expect(allViaMax[0]).to.equal(k0);
    });

    it("Should support xnsName overloads for getRouteKeyCount and getRouteKeys", async function () {
      const { routes, owner, buildTarget } = await loadFixture(deployFixture);
      await routes.connect(owner).createRoute(LABEL, NAMESPACE, ROUTE_LABEL, buildTarget, RT0);

      expect(await routes["getRouteKeyCount(string)"](XNS_NAME)).to.equal(1n);
      const keys = await routes["getRouteKeys(string,uint256,uint256)"](XNS_NAME, 0, 1);
      expect(keys.length).to.equal(1);
      expect(keys[0]).to.equal(routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL));
    });
  });

  describe("isValidRouteLabel", function () {
    it("Should expose isValidRouteLabel consistent with mutators", async function () {
      const { routes } = await loadFixture(deployFixture);
      expect(await routes.isValidRouteLabel("")).to.equal(false);
      expect(await routes.isValidRouteLabel(ROUTE_LABEL)).to.equal(true);
      expect(await routes.isValidRouteLabel("a".repeat(33))).to.equal(false);
      expect(await routes.isValidRouteLabel("-bad")).to.equal(false);
      expect(await routes.isValidRouteLabel("bad-")).to.equal(false);
      expect(await routes.isValidRouteLabel("bad--label")).to.equal(false);
      expect(await routes.isValidRouteLabel("Bad")).to.equal(false);
    });
  });
});
