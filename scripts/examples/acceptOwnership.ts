/**
 * Accept a pending transfer of the contract's ERC-173 identity ownership.
 *
 * This ownership does not grant any authority over routes. The signer must equal
 * `pendingOwner()`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/acceptOwnership.ts --network <network_name>`
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

const signerIndex = 0;

async function main() {
  const networkName = hre.network.name;
  const { ethers } = hre;
  const contractAddress = XNS_ROUTES_ADDRESS[networkName];
  if (!contractAddress) {
    throw new Error(
      `XNSRoutes address not set for network: ${networkName}. Set XNS_ROUTES_ADDRESS in constants/addresses.ts`,
    );
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const signer = (await ethers.getSigners())[signerIndex];
  const pendingOwner = await routes.pendingOwner();

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Current owner: ${GREEN}${await routes.owner()}${RESET}`);
  console.log(`Pending owner: ${GREEN}${pendingOwner}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  console.log(
    `Balance: ${GREEN}${formatEther(await ethers.provider.getBalance(signer.address))} ETH${RESET}\n`,
  );

  if (signer.address.toLowerCase() !== pendingOwner.toLowerCase()) {
    throw new Error("Configured signer is not pendingOwner()");
  }

  const tx = await routes.connect(signer).acceptOwnership();
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}`);
  await tx.wait();

  console.log(`${GREEN}✓ Ownership accepted. owner=${await routes.owner()}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
