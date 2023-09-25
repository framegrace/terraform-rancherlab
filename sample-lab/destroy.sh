#!/bin/bash
kind delete clusters upc-rancher upc-sample-0 upc-sample-1
rm -rf storage/upc-rancher/*
rm terraform.tfstate
