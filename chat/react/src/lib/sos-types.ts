export type RoomMode = 'rotating' | 'fixed';

export type ChatMessage = {
  id: string;
  sender: string;
  content: string;
  timestamp: number;
  system?: boolean;
  own?: boolean;
};
