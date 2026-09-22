import { PrismaClient } from "@prisma/client";

const globalForPrisma = global as unknown as { prisma: PrismaClient };

// `next build` imports this module while rendering metadata (app/layout.tsx,
// app/icon.tsx). PrismaClient throws immediately when DATABASE_URL is unset,
// which fails the image build. Zeabur's MySQL host is only reachable at
// runtime, so during the production build use a placeholder that never
// connects. Callers already fall back when the query fails. A real
// DATABASE_URL is still required once the server is running.
if (
  !process.env.DATABASE_URL &&
  process.env.NEXT_PHASE === "phase-production-build"
) {
  process.env.DATABASE_URL = "mysql://build:build@127.0.0.1:3306/wa_akg_build";
}

export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    log: ["warn", "error"],
  });

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
