const { ethers } = require("hardhat")
const { expect, assert } = require("chai")
const { time } = require("./utilities")

describe("WRAToken", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.owner = this.signers[0]

        this.genesis = this.signers[1]
        this.stake = this.signers[2]
        this.wrapfi = this.signers[3]
        this.dev = this.signers[4]
        this.eco = this.signers[5]

        this.WRAToken = await ethers.getContractFactory("WRAToken")
        this.wra = await this.WRAToken.deploy(100, this.genesis.address, this.stake.address,
            this.wrapfi.address, this.dev.address, this.eco.address)

        await this.wra.deployed()
    })
    it("should set correct state variables", async function () {
        expect(await this.wra.startAtBlock()).to.equal("1")
        expect(await this.wra.balanceOf(this.genesis.address)).to.equal("10000000000000000000000000");
        expect(await this.wra.balanceOf(this.owner.address)).to.equal("90000000000000000000000000");
        expect(await this.wra.balanceOf(this.stake.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.wrapfi.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.dev.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.eco.address)).to.equal("0");

        expect(await this.wra.totalSupply()).to.equal("100000000000000000000000000");

    })
    it("should not mint other than owner", async function () {

        let err
        try {
            await this.wra.connect(this.genesis).unLockForStakingReserve()
        } catch (e) {
            err = e
        }
        assert.equal(err.toString(), "Error: VM Exception while processing transaction: revert Ownable: caller is not the owner")


        err = ""
        try {
            await this.wra.connect(this.owner).unLockFor()
        } catch (e) {
            err = e
        }
        assert.equal(err.toString(), "TypeError: this.wra.connect(...).unLockFor is not a function")


    })


    it("should not unlock before one year", async function () {

        await this.wra.connect(this.owner).unLockForStakingReserve()
        await this.wra.connect(this.owner).unLockForWrapFiUsers()
        await this.wra.connect(this.owner).unLockForDevFund()
        await this.wra.connect(this.owner).unLockForEcoFund()
        expect(await this.wra.balanceOf(this.stake.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.wrapfi.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.dev.address)).to.equal("0");
        expect(await this.wra.balanceOf(this.eco.address)).to.equal("0");

    })

    it("should  unlock after one year", async function () {

        await time.advanceBlockTo("100");
        await this.wra.connect(this.owner).unLockForStakingReserve();//block 101
        expect(await this.wra.balanceOf(this.stake.address)).to.equal("6000000000000000000000000");

        // await time.advanceBlockTo("200");
        // await this.wra.connect(this.owner).mintForStakingReserve();//block 201
        // expect(await this.wra.balanceOf(this.stake.address)).to.equal("10500000000000000000000000");

        // await time.advanceBlockTo("300");
        // await this.wra.connect(this.owner).unLockForStakingReserve();//block 301
        // expect(await this.wra.balanceOf(this.stake.address)).to.equal("13500000000000000000000000");

        await time.advanceBlockTo("400");
        await this.wra.connect(this.owner).unLockForStakingReserve();//block 401
        expect(await this.wra.balanceOf(this.stake.address)).to.equal("15000000000000000000000000");
    })

    it("should  transfer", async function () {
    
        await this.wra.connect(this.genesis).transfer(this.dev.address, '1000000000000000000000000')
        expect(await this.wra.balanceOf(this.genesis.address)).to.equal("9000000000000000000000000");
        expect(await this.wra.balanceOf(this.dev.address)).to.equal("1000000000000000000000000");
    })
})