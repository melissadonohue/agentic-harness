/**
 * Agentic Harness — Database Seeder
 *
 * Produces deterministic, reproducible test data for dispatch environments.
 * Uses @faker-js/faker with a fixed seed so every run generates identical data.
 *
 * Usage:
 *   DATABASE_URL=postgresql://... npx tsx scripts/seed.ts
 *
 * The script is safe to run multiple times — it truncates tables before inserting.
 * When the schema is still stubbed (no tables exist), it exits gracefully.
 */

import { faker } from '@faker-js/faker';
import postgres from 'postgres';

// ---------------------------------------------------------------------------
// Fixed seed for deterministic output
// ---------------------------------------------------------------------------
const FAKER_SEED = 42;
faker.seed(FAKER_SEED);

// ---------------------------------------------------------------------------
// Database connection
// ---------------------------------------------------------------------------
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('[seed] ERROR: DATABASE_URL environment variable is required.');
  process.exit(1);
}

const sql = postgres(DATABASE_URL, {
  max: 1,
  onnotice: () => {}, // Suppress notices
});

// ---------------------------------------------------------------------------
// Seed data generators
// ---------------------------------------------------------------------------

/**
 * Generate deterministic user records.
 * These represent the base user set available in every dispatch environment.
 */
function generateUsers(count: number) {
  return Array.from({ length: count }, (_, i) => ({
    id: faker.string.uuid(),
    email: faker.internet.email().toLowerCase(),
    name: faker.person.fullName(),
    role: i === 0 ? 'admin' : 'member',
    created_at: faker.date.past({ years: 1 }).toISOString(),
    updated_at: faker.date.recent({ days: 30 }).toISOString(),
  }));
}

/**
 * Generate sample project records linked to users.
 */
function generateProjects(users: ReturnType<typeof generateUsers>, count: number) {
  return Array.from({ length: count }, () => ({
    id: faker.string.uuid(),
    name: faker.company.buzzPhrase(),
    description: faker.lorem.sentence(),
    owner_id: faker.helpers.arrayElement(users).id,
    created_at: faker.date.past({ years: 1 }).toISOString(),
    updated_at: faker.date.recent({ days: 30 }).toISOString(),
  }));
}

// ---------------------------------------------------------------------------
// Main seeding logic
// ---------------------------------------------------------------------------
async function seed() {
  console.log('[seed] Starting database seed...');
  console.log(`[seed] Faker seed: ${FAKER_SEED}`);
  console.log(`[seed] Database: ${DATABASE_URL!.replace(/\/\/.*@/, '//<redacted>@')}`);

  // Check if any tables exist — if the schema is still stubbed, exit gracefully
  const tables = await sql`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY tablename
  `;

  if (tables.length === 0) {
    console.log('[seed] No tables found in public schema. Schema may be stubbed.');
    console.log('[seed] Skipping seed — run migrations first to create tables.');
    await sql.end();
    return;
  }

  console.log(
    `[seed] Found ${tables.length} table(s): ${tables.map((t) => t.tablename).join(', ')}`,
  );

  // Generate deterministic data
  const users = generateUsers(5);
  const projects = generateProjects(users, 3);

  // Seed each table if it exists
  const tableNames = new Set(tables.map((t) => t.tablename));

  if (tableNames.has('users')) {
    console.log('[seed] Seeding users...');
    await sql`TRUNCATE TABLE users CASCADE`;
    for (const user of users) {
      await sql`
        INSERT INTO users (id, email, name, role, created_at, updated_at)
        VALUES (${user.id}, ${user.email}, ${user.name}, ${user.role}, ${user.created_at}, ${user.updated_at})
      `;
    }
    console.log(`[seed]   Inserted ${users.length} users`);
  }

  if (tableNames.has('projects')) {
    console.log('[seed] Seeding projects...');
    await sql`TRUNCATE TABLE projects CASCADE`;
    for (const project of projects) {
      await sql`
        INSERT INTO projects (id, name, description, owner_id, created_at, updated_at)
        VALUES (${project.id}, ${project.name}, ${project.description}, ${project.owner_id}, ${project.created_at}, ${project.updated_at})
      `;
    }
    console.log(`[seed]   Inserted ${projects.length} projects`);
  }

  // Export seed data as JSON for reference (useful for test fixtures)
  const seedManifest = {
    seed: FAKER_SEED,
    generated_at: new Date().toISOString(),
    counts: {
      users: users.length,
      projects: projects.length,
    },
    users: users.map((u) => ({ id: u.id, email: u.email, role: u.role })),
  };

  console.log('[seed] Seed manifest:');
  console.log(JSON.stringify(seedManifest, null, 2));

  await sql.end();
  console.log('[seed] Seeding complete.');
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
seed().catch((err) => {
  console.error('[seed] Fatal error:', err);
  process.exit(1);
});
