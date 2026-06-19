import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/onboarding_models.dart';

void main() {
  group('Onboarding Models Test', () {
    group('OnboardingPageData', () {
      test('should correctly assign all required properties', () {
        const pageData = OnboardingPageData(
          title: 'Welcome',
          subtitle: 'Subtitle',
          type: OnboardingPageType.welcome,
        );

        expect(pageData.title, 'Welcome');
        expect(pageData.subtitle, 'Subtitle');
        expect(pageData.description, isNull);
        expect(pageData.features, isNull);
        expect(pageData.type, OnboardingPageType.welcome);
      });

      test('should correctly assign all optional properties', () {
        const feature = OnboardingFeature(
          title: 'Feature',
          description: 'Desc',
          icon: Icons.star,
        );
        const pageData = OnboardingPageData(
          title: 'Features',
          subtitle: 'Features Subtitle',
          description: 'Description',
          features: [feature],
          type: OnboardingPageType.features,
        );

        expect(pageData.title, 'Features');
        expect(pageData.subtitle, 'Features Subtitle');
        expect(pageData.description, 'Description');
        expect(pageData.features, isNotNull);
        expect(pageData.features!.length, 1);
        expect(pageData.features!.first, feature);
        expect(pageData.type, OnboardingPageType.features);
      });
    });

    group('OnboardingFeature', () {
      test('should correctly assign all properties with default values', () {
        const feature = OnboardingFeature(
          title: 'Feature',
          description: 'Desc',
          icon: Icons.star,
        );

        expect(feature.title, 'Feature');
        expect(feature.description, 'Desc');
        expect(feature.icon, Icons.star);
        expect(feature.isHighlight, isFalse);
      });

      test('should correctly override default value', () {
        const feature = OnboardingFeature(
          title: 'Feature',
          description: 'Desc',
          icon: Icons.star,
          isHighlight: true,
        );

        expect(feature.isHighlight, isTrue);
      });
    });

    group('OnboardingPreference', () {
      test('should correctly assign properties properly', () {
        const pref = OnboardingPreference<bool>(
          key: 'sync_enabled',
          title: 'Sync',
          description: 'Enable Sync',
          defaultValue: true,
          type: OnboardingPreferenceType.toggle,
        );

        expect(pref.key, 'sync_enabled');
        expect(pref.title, 'Sync');
        expect(pref.description, 'Enable Sync');
        expect(pref.defaultValue, isTrue);
        expect(pref.options, isNull);
        expect(pref.type, OnboardingPreferenceType.toggle);
      });
    });

    group('OnboardingPreferenceOption', () {
      test('should correctly assign value, label, and description', () {
        const option = OnboardingPreferenceOption<String>(
          value: 'dark',
          label: 'Dark Mode',
          description: 'Uses dark colors',
        );

        expect(option.value, 'dark');
        expect(option.label, 'Dark Mode');
        expect(option.description, 'Uses dark colors');
      });
    });

    group('OnboardingState', () {
      test('should have correct default values', () {
        const state = OnboardingState();

        expect(state.currentPageIndex, 0);
        expect(state.isCompleting, isFalse);
        expect(state.preferences, isEmpty);
        expect(state.canGoNext, isTrue);
        expect(state.canGoPrevious, isFalse);
      });

      test('copyWith should update specific fields or use existing', () {
        const initialState = OnboardingState();
        final updatedState = initialState.copyWith(
          currentPageIndex: 1,
          isCompleting: true,
          canGoNext: false,
          canGoPrevious: true,
          preferences: {'theme': 'dark'},
        );

        expect(updatedState.currentPageIndex, 1);
        expect(updatedState.isCompleting, isTrue);
        expect(updatedState.canGoNext, isFalse);
        expect(updatedState.canGoPrevious, isTrue);
        expect(updatedState.preferences['theme'], 'dark');

        final partialUpdate = updatedState.copyWith(currentPageIndex: 2);
        expect(partialUpdate.currentPageIndex, 2);
        expect(partialUpdate.isCompleting, isTrue);
        expect(partialUpdate.canGoNext, isFalse);
        expect(partialUpdate.canGoPrevious, isTrue);
        expect(partialUpdate.preferences['theme'], 'dark');
      });

      test('updatePreference should return new state and keep original intact',
          () {
        const initialState = OnboardingState(preferences: {'theme': 'light'});
        final updatedState = initialState.updatePreference('theme', 'dark');

        expect(initialState.preferences['theme'], 'light');
        expect(updatedState.preferences['theme'], 'dark');
        expect(updatedState.currentPageIndex, initialState.currentPageIndex);
      });

      test('getPreference should retrieve casted value or null', () {
        const state = OnboardingState(preferences: {
          'theme': 'dark',
          'sync_enabled': true,
        });

        expect(state.getPreference<String>('theme'), 'dark');
        expect(state.getPreference<bool>('sync_enabled'), isTrue);
        expect(state.getPreference<int>('missing_key'), isNull);
      });
    });
  });
}
