import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/yt_parser.dart';

Map<String, dynamic> lockup(String id, List<List<String>> rows, {String duration = '4:13'}) => {
      'lockupViewModel': {
        'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
        'contentId': id,
        'contentImage': {
          'thumbnailViewModel': {
            'image': {
              'sources': [
                {'url': 'https://i.ytimg.com/vi/$id/hq.jpg', 'width': 336}
              ]
            },
            'overlays': [
              {
                'thumbnailBottomOverlayViewModel': {
                  'badges': [
                    {
                      'thumbnailBadgeViewModel': {'text': duration, 'badgeStyle': 'THUMBNAIL_OVERLAY_BADGE_STYLE_DEFAULT'}
                    }
                  ]
                }
              }
            ],
          }
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': 'Video $id'},
            'metadata': {
              'contentMetadataViewModel': {
                'metadataRows': [
                  for (final r in rows)
                    {
                      'metadataParts': [
                        for (final p in r) {'text': {'content': p}}
                      ]
                    }
                ]
              }
            },
          }
        },
      }
    };

void main() {
  test('lockup metadata is classified regardless of row layout', () {
    final videos = YtParser.videos({
      'contents': [
        lockup('aaaaaaaaaaa', [
          ['Channel A'],
          ['1.2M views', '3 days ago']
        ]),
        lockup('bbbbbbbbbbb', [
          ['Topic B', '88K views']
        ]),
        lockup('ccccccccccc', [
          ['552K', '10d ago']
        ]),
      ]
    });

    expect(videos.map((v) => v.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    expect(videos[0].channelName, 'Channel A');
    expect(videos[0].viewText, '1.2M views');
    expect(videos[0].publishedText, '3 days ago');
    expect(videos[0].duration, 253);
    expect(videos[1].channelName, 'Topic B');
    expect(videos[1].viewText, '88K views');
    expect(videos[2].channelName, '');
    expect(videos[2].viewText, '552K views');
    expect(videos[2].viewCount, 552000);
  });

  test('ad renderers are never returned', () {
    final videos = YtParser.videos({
      'contents': [
        {
          'adSlotRenderer': {
            'content': lockup('adadadadada', [
              ['Advertiser']
            ])
          }
        },
        lockup('realvideo01', [
          ['Creator'],
          ['10 views', '1 hour ago']
        ]),
      ]
    });
    expect(videos.map((v) => v.id), ['realvideo01']);
  });

  test('counts and durations parse', () {
    expect(YtParser.parseCount('58,560,484 views'), 58560484);
    expect(YtParser.parseCount('1.8B views'), 1800000000);
    expect(YtParser.parseDuration('6:10:58'), 22258);
  });

  test('comments are read from entity payloads', () {
    final page = YtParser.comments({
      'onResponseReceivedEndpoints': [
        {
          'reloadContinuationItemsCommand': {
            'continuationItems': [
              {
                'commentThreadRenderer': {
                  'commentViewModel': {
                    'commentViewModel': {'commentId': 'c1'}
                  }
                }
              },
              {
                'continuationItemRenderer': {
                  'continuationEndpoint': {
                    'continuationCommand': {'token': 'NEXT'}
                  }
                }
              },
            ]
          }
        }
      ],
      'frameworkUpdates': {
        'entityBatchUpdate': {
          'mutations': [
            {
              'payload': {
                'commentEntityPayload': {
                  'properties': {
                    'commentId': 'c1',
                    'content': {'content': 'Great video'},
                    'publishedTime': '2 days ago'
                  },
                  'author': {'displayName': '@someone', 'avatarThumbnailUrl': 'https://x/a.jpg'},
                  'toolbar': {'likeCountNotliked': '1.2K', 'replyCount': '4'},
                }
              }
            }
          ]
        }
      },
    });
    expect(page.comments.single.text, 'Great video');
    expect(page.comments.single.likeCount, 1200);
    expect(page.continuation, 'NEXT');
  });
}
