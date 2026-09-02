import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get('/api/health', (_req: Request, res: Response) => {
  res.status(200).json({ status: 'ok' });
});

if (process.env.NODE_ENV !== 'test') {
  app.listen(port, () => {
    console.log(`VessPay backend running on port ${port}`);
  });
}

export default app;
