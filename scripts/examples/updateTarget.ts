/**
 * Update the build target for an existing route. Emits `RouteSet` only if the target changes.
 * Caller must be the address XNS currently resolves for `xnsName`.
 * Reverts if the route or route book is frozen, or if `newTarget` is zero.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/updateTarget.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/updateTarget.ts --network sepolia`
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
const chain = "eth";
const route = "register-name";
/** Must be non-zero */
const newTarget = "0x0000000000000000000000000000000000000002";
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
  if (!hre.ethers.isAddress(newTarget)) {
    throw new Error(`Invalid newTarget address: ${newTarget}`);
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
  console.log(`chain: ${GREEN}${chain}${RESET}`);
  console.log(`route: ${GREEN}${route}${RESET}`);
  console.log(`newTarget: ${GREEN}${newTarget}${RESET}\n`);

  const tx = await routes.connect(signer).updateTarget(xnsName, chain, route, newTarget);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const t = await routes.getRoute(xnsName, chain, route);
  console.log(`${GREEN}✓ Confirmed. getRoute → target=${t}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
