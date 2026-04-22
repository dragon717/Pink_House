import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppLogger } from '../utils/AppLogger';

const WARDROBE_IMAGE_DIR = 'wardrobe_images';

export class WardrobeImageStore {
  static async pickImages(maxSelectNumber: number): Promise<string[]> {
    AppLogger.info(`[WardrobeImageStore] pickImages start, max=${maxSelectNumber}`);
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxSelectNumber;

    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    const uris = result.photoUris ?? [];
    AppLogger.info(`[WardrobeImageStore] pickImages result=${uris.length}`);
    return uris;
  }

  static async persistPickedImage(context: common.Context, sourceUri: string): Promise<string> {
    if (sourceUri.length === 0) {
      return '';
    }

    const targetDir = `${context.filesDir}/${WARDROBE_IMAGE_DIR}`;
    const suffix = WardrobeImageStore.extractSuffix(sourceUri);
    const targetPath = `${targetDir}/wardrobe_${Date.now()}_${Math.floor(Math.random() * 100000)}${suffix}`;

    try {
      await fs.mkdir(targetDir, true);
    } catch (error) {
      AppLogger.warn(`[WardrobeImageStore] mkdir skipped/failed: ${JSON.stringify(error)}`);
    }

    try {
      AppLogger.info(`[WardrobeImageStore] copy start: ${sourceUri} -> ${targetPath}`);
      await fs.copyFile(sourceUri, targetPath);
      const fileUri = `file://${targetPath}`;
      AppLogger.info(`[WardrobeImageStore] copy success: ${fileUri}`);
      return fileUri;
    } catch (error) {
      AppLogger.error(`[WardrobeImageStore] copy failed, fallback to picker uri: ${JSON.stringify(error)}`);
      return sourceUri;
    }
  }

  private static extractSuffix(uri: string): string {
    const cleanUri = uri.split('?')[0];
    const dotIndex = cleanUri.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < cleanUri.length - 1) {
      const suffix = cleanUri.substring(dotIndex);
      if (suffix.length <= 8) {
        return suffix;
      }
    }
    return '.jpg';
  }
}
