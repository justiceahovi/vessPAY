import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { checkDatabaseConnection, prisma } from './lib/db';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/api/health', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'ok' });
});

async function start() {
  console.log('Checking database connection...');
  await checkDatabaseConnection();
  console.log('Database connection: OK');

  app.listen(port, () => {
    console.log(`VessPay backend running on port ${port}`);
  });
}

if (process.env.NODE_ENV !== 'test') {
  start().catch((err) => {
    console.error('Failed to start server:', err);
    process.exit(1);
  });
}

export { prisma };
export default app;