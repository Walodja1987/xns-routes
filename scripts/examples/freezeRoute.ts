/**
 * Permanently freeze a single route (target can no longer change; isActive can still toggle).
 * Caller must be the address XNS currently resolves for `xnsName`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/freezeRoute.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/freezeRoute.ts --network sepolia`
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
const routeScope = "eth";
const routeLabel = "register-name";
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
  console.log(`routeScope: ${GREEN}${routeScope}${RESET}`);
  console.log(`routeLabel: ${GREEN}${route}${RESET}\n`);

  const tx = await routes.connect(signer).freezeRoute(xnsName, routeScope, route);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const record = await routes.getRouteRecord(xnsName, routeScope, routeLabel);
  console.log(`${GREEN}✓ Confirmed. isFrozen=${record.isFrozen}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
