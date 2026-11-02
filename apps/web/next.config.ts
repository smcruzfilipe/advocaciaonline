import type { NextConfig } from "next";

const config: NextConfig = {
  output: "standalone",
  // Invitation and email verification traffic must not enter dev logs.
  logging: false,
  poweredByHeader: false,
};

export default config;
