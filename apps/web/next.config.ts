import type { NextConfig } from "next";

const config: NextConfig = {
  // OAuth callback query parameters and invitation traffic must not enter dev logs.
  logging: false,
  poweredByHeader: false,
};

export default config;
