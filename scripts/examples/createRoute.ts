/**
 * Register a new route under `(xnsName, routeScope, routeLabel)`. Reverts if that key already exists.
 * Caller must be the address XNS currently resolves for `xnsName`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/createRoute.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/createRoute.ts --network sepolia`
 *
 * REQUIRED SETUP:
 * - MNEMONIC, network RPC (see docs/DEV_NOTES.md)
 * - Set `XNS_ROUTES_ADDRESS.<network>` in constants/addresses.ts
 */

import hre from "hardhat";
import { formatEther } from "ethers";
import { XNS_ROUTES_ADDRESS } from "../../constants/addresses";

const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";

/*//////////////////////////////////////////////////////////////
                            USER INPUTS
//////////////////////////////////////////////////////////////*/

const xnsName = "xns.action";
/** Optional route scope (path segment before `:`), e.g. `eth` in `xns.action/eth:register-name/...` */
const routeScope = "eth";
const routeLabel = "register-name";

/** Build contract address for this route */
const target = "0x0000000000000000000000000000000000000001";

/** Parser hint; semantics are offchain (0 = target is the answer, 1 = query target, 2 = executable calldata) */
const routeType = 0;

/**
 * Optional explicit `activeController`. When set, calls `createRouteWithController`
 * instead of `createRoute` (which defaults to activeController=XNS name owner; both use isActive=true).
 */
const useControllerOverride = false;
const activeControllerOverride = "0x0000000000000000000000000000000000000002";

/** Signer index (0 = first account from mnemonic) */
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;

  if (!hre.ethers.isAddress(target)) {
    throw new Error(`Invalid target address: ${target}`);
  }

  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await hre.ethers.getContractAt("XNSRoutes", contractAddress);
  const signers = await hre.ethers.getSigners();
  const signer = signers[signerIndex];

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  const balance = await hre.ethers.provider.getBalance(signer.address);
  console.log(`Balance: ${GREEN}${formatEther(balance)} ETH${RESET}`);
  console.log(`xnsName: ${GREEN}${xnsName}${RESET}`);
  console.log(`routeScope: ${GREEN}${routeScope}${RESET}`);
  console.log(`routeLabel: ${GREEN}${routeLabel}${RESET}`);
  console.log(`target: ${GREEN}${target}${RESET}`);
  console.log(`routeType: ${GREEN}${routeType}${RESET}`);
  if (useControllerOverride) {
    console.log(`activeController: ${GREEN}${activeControllerOverride}${RESET} (override)\n`);
  } else {
    console.log(`isActive: ${GREEN}true (default)${RESET}`);
    console.log(`activeController: ${GREEN}XNS name owner (default)${RESET}\n`);
  }

  const tx = useControllerOverride
    ? await routes
        .connect(signer)
        .createRouteWithController(
          xnsName,
          routeScope,
          routeLabel,
          target,
          routeType,
          activeControllerOverride,
        )
    : await routes.connect(signer).createRoute(xnsName, routeScope, routeLabel, target, routeType);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const record = await routes.getRouteRecord(xnsName, routeScope, routeLabel);
  console.log(
    `${GREEN}✓ Confirmed. getRouteRecord → target=${record.target} routeType=${record.routeType} isActive=${record.isActive} activeController=${record.activeController}${RESET}\n`,
  );
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
