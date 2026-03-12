import fs from 'fs';
import path from 'path';
import { Config } from './types';

export function loadConfig(configPath: string): Config {
  const absolutePath = path.resolve(configPath);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Configuration file not found at ${absolutePath}`);
  }
  const fileContent = fs.readFileSync(absolutePath, 'utf-8');
  try {
    return JSON.parse(fileContent) as Config;
  } catch (error) {
    throw new Error(`Failed to parse configuration file: ${(error as Error).message}`);
  }
}
