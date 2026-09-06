import { prisma } from '../src/lib/db';

async function verifySchema() {
  console.log('--- Verifying Database Schema for T1.1 ---');

  // 1. Check tables and columns
  const tables = ['users', 'travel_profiles', 'wallets'];
  for (const table of tables) {
    const columns: any = await prisma.$queryRawUnsafe(`
      SELECT column_name, data_type, udt_name, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = '${table}'
      ORDER BY ordinal_position;
    `);
    console.log(`\nTable [${table}] columns (${columns.length}):`);
    for (const col of columns) {
      console.log(
        `  - ${col.column_name}: ${col.udt_name} (nullable: ${col.is_nullable}, default: ${col.column_default})`
      );
    }
  }

  // 2. Test Prisma Client operations (create user -> create travel profile -> create wallet)
  console.log('\n--- Testing CRUD operations via Prisma Client ---');
  const testUser = await prisma.user.create({
    data: {
      firstName: 'Test',
      lastName: 'User',
      email: `test-${Date.now()}@vesspay.com`,
      passwordHash: 'hashed_pw_placeholder',
      country: 'GH',
      nationality: 'Ghanaian',
      travelProfiles: {
        create: {
          destinationCountry: 'GH',
          destinationCurrency: 'GHS',
          isActive: true,
        },
      },
      wallets: {
        create: {
          currency: 'USD',
          balance: 100.50,
        },
      },
    },
    include: {
      travelProfiles: true,
      wallets: true,
    },
  });

  console.log('Created User ID:', testUser.id);
  console.log('Created TravelProfile ID:', testUser.travelProfiles[0].id);
  console.log('Created Wallet ID:', testUser.wallets[0].id, 'Balance:', testUser.wallets[0].balance.toString());

  // 3. Test cascade deletion
  await prisma.user.delete({
    where: { id: testUser.id },
  });

  const profileCount = await prisma.travelProfile.count({ where: { userId: testUser.id } });
  const walletCount = await prisma.wallet.count({ where: { userId: testUser.id } });

  console.log(`After deleting user: orphaned profiles = ${profileCount}, orphaned wallets = ${walletCount}`);
  if (profileCount !== 0 || walletCount !== 0) {
    throw new Error('Cascade delete failed!');
  }

  console.log('\nAll schema verification checks passed successfully!');
}

verifySchema()
  .catch((err) => {
    console.error('Verification failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
