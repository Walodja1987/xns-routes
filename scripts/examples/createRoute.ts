/**
 * Register a new route under `(label, namespace, routeLabel)`. Reverts if that key already exists.
 * Caller must be the address XNS currently resolves for `label@namespace`.
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

const label = "xns";
const namespace = "action";
const routeLabel = "register-name";

/**
 * Opaque `bytes` target (1–256 bytes). For a 20-byte EVM address payload, pass the address
 * hex and convert with `ethers.getBytes` / `ethers.hexlify`.
 */
const targetAddress = "0x0000000000000000000000000000000000000001";

/** Parser hint; semantics are offchain (0 = EVM address, 1 = resolver, 2 = app-defined) */
const routeType = 0;

/** Signer index (0 = first account from mnemonic) */
const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
  const { ethers } = hre;

  if (!ethers.isAddress(targetAddress)) {
    throw new Error(`Invalid target address: ${targetAddress}`);
  }
  const target = ethers.hexlify(ethers.getBytes(targetAddress));

  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const signers = await ethers.getSigners();
  const signer = signers[signerIndex];

  const xnsName = `${label}@${namespace}`;

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  const balance = await ethers.provider.getBalance(signer.address);
  console.log(`Balance: ${GREEN}${formatEther(balance)} ETH${RESET}`);
  console.log(`xnsName: ${GREEN}${xnsName}${RESET}`);
  console.log(`routeLabel: ${GREEN}${routeLabel}${RESET}`);
  console.log(`target: ${GREEN}${target}${RESET} (${ethers.getBytes(target).length} bytes)`);
  console.log(`routeType: ${GREEN}${routeType}${RESET}`);
  console.log(`isActive: ${GREEN}true (default)${RESET}\n`);

  const tx = await routes.connect(signer).createRoute(label, namespace, routeLabel, target, routeType);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}\n`);
  console.log("Waiting for confirmation...\n");
  await tx.wait();

  const record = await routes.getRouteRecord(label, namespace, routeLabel);
  console.log(
    `${GREEN}✓ Confirmed. getRouteRecord → target=${record.target} routeType=${record.routeType} isActive=${record.isActive}${RESET}\n`,
  );
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
