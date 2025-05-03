from microbit import *
import radio

# Morse code dictionary
morse_dict = {
    '.-': 'A', '-...': 'B', '-.-.': 'C', '-..': 'D', '.': 'E',
    '..-.': 'F', '--.': 'G', '....': 'H', '..': 'I', '.---': 'J',
    '-.-': 'K', '.-..': 'L', '--': 'M', '-.': 'N', '---': 'O',
    '.--.': 'P', '--.-': 'Q', '.-.': 'R', '...': 'S', '-': 'T',
    '..-': 'U', '...-': 'V', '.--': 'W', '-..-': 'X', '-.--': 'Y',
    '--..': 'Z', '-----': '0', '.----': '1', '..---': '2',
    '...--': '3', '....-': '4', '.....': '5', '-....': '6',
    '--...': '7', '---..': '8', '----.': '9'
}

radio.on()
radio.config(group=1)

current_symbol = ""
decoded_word = ""
display.scroll("ENTER")

def check_incoming():
    incoming = radio.receive()
    if incoming:
        display.scroll("RECEIVING")
        sleep(200)
        display.scroll(incoming)
        sleep(500)
        display.scroll("ENTER")

while True:
    check_incoming()

    if button_a.is_pressed() and button_b.is_pressed():
        start = running_time()
        while button_a.is_pressed() and button_b.is_pressed():
            sleep(10)
            check_incoming()  # Allow interrupt check while holding

        duration = running_time() - start

        if duration > 1500:  # Long press
            if current_symbol:
                trimmed = current_symbol[1:-1] if len(current_symbol) > 2 else current_symbol[:1]
                if trimmed:
                    letter = morse_dict.get(trimmed, '?')
                    decoded_word += letter
                current_symbol = ""

            if decoded_word:
                word_to_send = decoded_word[:-1] if len(decoded_word) > 1 else decoded_word
                if word_to_send:
                    display.scroll("TRANSMITTING")
                    radio.send(word_to_send)
                    display.scroll("DONE")
                    sleep(200)
                    display.scroll("ENTER")
                else:
                    display.scroll("EMPTY")
                    sleep(200)
                    display.scroll("ENTER")
                decoded_word = ""
            else:
                display.scroll("ENTER")
            sleep(300)

        else:  # Short press: Letter end
            if current_symbol:
                trimmed = current_symbol[1:-1] if len(current_symbol) > 2 else current_symbol[:1]
                if trimmed:
                    letter = morse_dict.get(trimmed, '?')
                    decoded_word += letter
                    display.show(letter)
                else:
                    display.show('?')
            else:
                display.show('?')
            current_symbol = ""
            sleep(300)

    elif button_a.was_pressed():
        current_symbol += '-'
        display.show('-')
        sleep(150)

    elif button_b.was_pressed():
        current_symbol += '.'
        display.show('.')
        sleep(150)
