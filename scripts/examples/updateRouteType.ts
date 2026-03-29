/**
 * Update routeType for an existing route. Emits `RouteSet` only if the type changes.
 * Caller must be the address XNS currently resolves for `xnsName`.
 * Reverts if the route or route book is frozen.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/updateRouteType.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/updateRouteType.ts --network sepolia`
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
const routePrefix = "eth";
const route = "register-name";
/** Opaque parser hint; semantics are offchain */
const newRouteType = 1;
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
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
  console.log(`routePrefix: ${GREEN}${routePrefix}${RESET}`);
  console.log(`route: ${GREEN}${route}${RESET}`);
  console.log(`newRouteType: ${GREEN}${newRouteType}${RESET}\n`);

  const tx = await routes.connect(signer).updateRouteType(xnsName, routePrefix, route, newRouteType);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const [, , , rt] = await routes.getRouteInfo(xnsName, routePrefix, route);
  console.log(`${GREEN}✓ Confirmed. getRouteInfo → routeType=${rt}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
