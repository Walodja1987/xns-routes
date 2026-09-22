/**
 * Start the two-step transfer of the contract's ERC-173 identity owner.
 *
 * This ownership does not grant any authority over routes. The nominated owner must
 * complete the transfer separately with `acceptOwnership`.
 *
 * USAGE:
 * `npx hardhat run scripts/examples/transferOwnership.ts --network <network_name>`
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

const newOwner = "0x0000000000000000000000000000000000000001";
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
  if (!ethers.isAddress(newOwner) || newOwner === ethers.ZeroAddress) {
    throw new Error(`Invalid new owner: ${newOwner}`);
  }

  const routes = await ethers.getContractAt("XNSRoutes", contractAddress);
  const signer = (await ethers.getSigners())[signerIndex];

  console.log(`\nNetwork: ${GREEN}${networkName}${RESET}`);
  console.log(`XNSRoutes: ${GREEN}${contractAddress}${RESET}`);
  console.log(`Current owner: ${GREEN}${await routes.owner()}${RESET}`);
  console.log(`Signer: ${GREEN}${signer.address}${RESET}`);
  console.log(
    `Balance: ${GREEN}${formatEther(await ethers.provider.getBalance(signer.address))} ETH${RESET}`,
  );
  console.log(`New owner: ${GREEN}${newOwner}${RESET}\n`);

  const tx = await routes.connect(signer).transferOwnership(newOwner);
  console.log(`Transaction hash: ${GREEN}${tx.hash}${RESET}`);
  await tx.wait();

  console.log(`${GREEN}✓ Transfer started. pendingOwner=${await routes.pendingOwner()}${RESET}\n`);
}

main().catch((error: unknown) => {
  console.error(RED + (error instanceof Error ? error.message : String(error)) + RESET);
  process.exitCode = 1;
});
