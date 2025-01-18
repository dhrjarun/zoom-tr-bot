#!/usr/bin/env python3
import socket
import os
import time
import assemblyai as aai


SOCKET_PATH = "/tmp/meeting.sock"
SAMPLE_RATE = 32000
BUFFER_SIZE = 10000
MAX_RETRIES = None  # No retry limit - will keep trying indefinitely
TRANSCRIPT_FILE = "./out/transcript.txt"

aai.settings.api_key = "f1d484315da24d979451138b4e523e43"

def on_data(transcript):
    print(f"Transcript: {transcript}")
    with open(TRANSCRIPT_FILE, 'a') as f:
        f.write(transcript)

def on_error(error):
    print(f"failed to transcribe: {error}")

def on_open():
    print("Connection opened")

def on_close():
    print("Connection closed")

def connect_to_socket():
    retries = 0
    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(SOCKET_PATH)
            print("Successfully connected to socket server")
            return client
        except socket.error as e:
            print(f"Server not available, retrying in 1 seconds... ({e})")
            client.close()
            time.sleep(1)
            retries += 1

            if MAX_RETRIES and retries >= MAX_RETRIES:
                print(f"Max retries ({MAX_RETRIES}) reached. Giving up.")
                return None

def read_and_transcribe():
    client = connect_to_socket()
    if not client:
        return False

    transcriber = aai.RealtimeTranscriber(on_data=on_data, on_error=on_error, on_open=on_open, on_close=on_close, sample_rate=SAMPLE_RATE)
    transcriber.connect()
    try:
        while True:
            data = client.recv(BUFFER_SIZE)
            if not data:
                print("No more data to read")
                break
            print("sending to assemblyai")
            transcriber.stream(data)
    except IOError as e:
        print(f"Error writing to file: {e}")
        return False
    except socket.error as e:
        print(f"Socket error: {e}")
        return False
    finally:
        client.close()
        transcriber.close()

    return True

def read_and_write_to_file(output_file):
    client = connect_to_socket()
    if not client:
        return False

    try:
        with open(output_file, 'wb') as f:
            while True:
                data = client.recv(BUFFER_SIZE)
                if not data:
                    break
                f.write(data)
    except IOError as e:
        print(f"Error writing to file: {e}")
        return False
    except socket.error as e:
        print(f"Socket error: {e}")
        return False
    finally:
        client.close()

    return True

def main():
    output_file = "./out/output.pcm"
    # success = read_and_write_to_file(output_file)
    success = read_and_transcribe()
    if success:
        print(f"Successfully transcribed audio to {TRANSCRIPT_FILE}")
    else:
        print("Failed to transcribe audio")

if __name__ == "__main__":
    main()
