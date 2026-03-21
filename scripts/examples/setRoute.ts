/**
 * Create or update a route (target + active + optional immediate freeze).
 * Caller must be the address XNS currently resolves for `baseName`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/setRoute.ts --network <network_name>`
 *
 * EXAMPLE:
 * `npx hardhat run scripts/examples/setRoute.ts --network sepolia`
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

const baseName = "xns.action";
/** Chain key (path segment before `:`), e.g. `eth` in `xns.action/eth:register-name/...` */
const chain = "eth";
const route = "register-name";

/** Build contract address for this route */
const target = "0x0000000000000000000000000000000000000001";

const isActive = true;

/** If true, route target cannot be changed after this tx */
const freezeImmediately = false;

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
  console.log(`baseName: ${GREEN}${baseName}${RESET}`);
  console.log(`chain: ${GREEN}${chain}${RESET}`);
  console.log(`route: ${GREEN}${route}${RESET}`);
  console.log(`target: ${GREEN}${target}${RESET}`);
  console.log(`isActive: ${GREEN}${isActive}${RESET}`);
  console.log(`freezeImmediately: ${GREEN}${freezeImmediately}${RESET}\n`);

  const tx = await routes
    .connect(signer)
    .setRoute(baseName, chain, route, target, isActive, freezeImmediately);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const [t, active, frozen] = await routes.getRouteInfo(baseName, chain, route);
  console.log(
    `${GREEN}✓ Confirmed. getRouteInfo → target=${t} isActive=${active} isFrozen=${frozen}${RESET}\n`,
  );
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
