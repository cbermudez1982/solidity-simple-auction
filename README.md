# Solidity Simple Auction

A simple smart contract for an auction in Solidity.

This contract deploys a simple auction system, that lasts for a day
 * it has a minimun bid value of 1.000.000 Wei and all bids have to be multiples of the min bid.
 * Only bidders distinct to the owner can use the bid() function
 * There can be partial claims of the deposited currency, leaving only the last bid of each address after every partial claim.
 * When Auction is over, the owner can send the reamining balances to each address discounting a 2% for gas purposes.
 * The owner can claim the remaining balance of the contract only after sending Ethers to the bidders have been done.
