import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/utils/agent_note_document_codec.dart';

void main() {
  group('AgentNoteDocumentCodec', () {
    test('normalizes rich text and derives the only plain-text value', () {
      final ops = AgentNoteDocumentCodec.validateAndNormalize(
        NoteDocumentKind.rich,
        const [
          {
            'insert': 'Heading',
            'attributes': {'bold': true}
          },
          {
            'insert': '\n',
            'attributes': {'header': 1}
          },
        ],
      );

      expect(AgentNoteDocumentCodec.plainTextOf(ops), 'Heading');
      expect(ops.last['attributes'], {'header': 1});
    });

    test('plain documents reject formatting and embeds', () {
      expect(
        () => AgentNoteDocumentCodec.validateAndNormalize(
          NoteDocumentKind.plain,
          const [
            {
              'insert': 'formatted',
              'attributes': {'bold': true}
            }
          ],
        ),
        throwsA(
          isA<AgentNoteDocumentException>().having(
            (error) => error.code,
            'code',
            'plain_attributes_not_allowed',
          ),
        ),
      );
      expect(
        () => AgentNoteDocumentCodec.validateAndNormalize(
          NoteDocumentKind.plain,
          const [
            {
              'insert': {'image': '/private/photo.jpg'}
            }
          ],
        ),
        throwsA(isA<AgentNoteDocumentException>()),
      );
    });

    test('rejects unsafe links and normalizes the final newline', () {
      expect(
        () => AgentNoteDocumentCodec.validateAndNormalize(
          NoteDocumentKind.rich,
          const [
            {
              'insert': 'click',
              'attributes': {'link': 'javascript:alert(1)'}
            }
          ],
        ),
        throwsA(
          isA<AgentNoteDocumentException>()
              .having((error) => error.code, 'code', 'unsafe_link'),
        ),
      );

      final ops = AgentNoteDocumentCodec.validateAndNormalize(
        NoteDocumentKind.plain,
        const [
          {'insert': 'plain'}
        ],
      );
      expect(ops, [
        {'insert': 'plain'},
        {'insert': '\n'},
      ]);
    });

    test('preserves supported editor styles and rejects invalid values', () {
      final normalized = AgentNoteDocumentCodec.validateAndNormalize(
        NoteDocumentKind.rich,
        [
          {
            'insert': 'styled',
            'attributes': {
              'font': 'serif',
              'size': 'small',
              'color': '#112233',
              'background': '#AABBCCDD',
            },
          },
          {
            'insert': '\n',
            'attributes': {'header': 2, 'align': 'center'},
          },
        ],
      );

      expect(normalized.first['attributes'], {
        'font': 'serif',
        'size': 'small',
        'color': '#112233',
        'background': '#AABBCCDD',
      });
      expect(
        () => AgentNoteDocumentCodec.validateAndNormalize(
          NoteDocumentKind.rich,
          [
            {
              'insert': 'bad\n',
              'attributes': {'header': 'huge'},
            },
          ],
        ),
        throwsA(
          isA<AgentNoteDocumentException>().having(
            (error) => error.code,
            'code',
            'invalid_attribute_value',
          ),
        ),
      );
    });

    test('sanitizes existing media before sending a document to a model', () {
      final sanitized = AgentNoteDocumentCodec.sanitizeForModel(const [
        {
          'insert': {'image': '/home/user/private.png'}
        },
        {'insert': '\n'},
      ]);

      expect(sanitized.first, {'insert': '[media]'});
      expect(sanitized.toString(), isNot(contains('/home/user')));
    });

    test('compares media references as a multiset', () {
      const image = {
        'insert': {'image': '/private/photo.jpg'}
      };
      const audio = {
        'insert': {'audio': '/private/voice.m4a'}
      };

      expect(
        AgentNoteDocumentCodec.hasSameEmbeds(
          const [image, audio, image],
          const [image, image, audio],
        ),
        isTrue,
      );
      expect(
        AgentNoteDocumentCodec.hasSameEmbeds(
          const [image, audio, image],
          const [image, audio],
        ),
        isFalse,
      );
      expect(
        AgentNoteDocumentCodec.hasSameEmbeds(
          const [image],
          const [audio],
        ),
        isFalse,
      );
    });
  });
}
