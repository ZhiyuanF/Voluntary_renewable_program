# Voluntary Renewable Program (VRP) Simulation

## Overview

This repository provides a MATLAB-based simulation environment using the ISO New England (ISO-NE) test system to evaluate the design and effectiveness of **Voluntary Renewable Programs (VRPs)**.

The framework integrates calibrated power-market simulation results, including grid emissions intensity, renewable generation, and wholesale electricity prices, with an economic model of voluntary renewable procurement. It examines how VRP pricing, revenue allocation, and renewable investment decisions evolve as renewable penetration increases.

The simulations investigate optimal VRP pricing, renewable capacity expansion, revenue sharing between utilities and renewable generators, and the long-run financial feasibility of voluntary renewable financing.

## Running the Simulations

The simulations are implemented in MATLAB. Open the repository directory in MATLAB and run the following scripts:

**1. Main Simulation**

`MAIN_simulation_V1.m`

Reproduces the baseline multi-period VRP simulation, including renewable capacity expansion, optimal pricing, grid emissions intensity, and revenue-sharing dynamics.

**2. Sensitivity Analysis**

`MAIN_simulation_sensitivity.m`

Reproduces the sensitivity analyses examining:

- Voluntary demand sensitivity and long-run financial feasibility.
- Robustness of the monotone reachability condition.
- Wholesale-market revenue erosion and its effects on generator support and renewable expansion.

Both scripts use the calibrated ISO-NE simulation data and supporting functions included in the repository.

## Research Context

The simulations support the research manuscript *Managing Voluntary Renewable Programs: Pricing, Revenue Allocation, and Renewable Expansion*, by Zhiyuan Fan, Tianyi Lin, and Bolun Xu.
