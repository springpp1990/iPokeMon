//
//  WildPokemonController.m
//  Pokemon
//
//  Created by Kaijie Yu on 4/2/12.
//  Copyright (c) 2012 Kjuly. All rights reserved.
//

#import "WildPokemonController.h"

#import "GlobalConstants.h"
#import "PokemonConstants.h"
#import "PokemonServerAPI.h"
#import "AppDelegate.h"
#import "WildPokemon+DataController.h"
#import "Pokemon+DataController.h"
#import "Move+DataController.h"
#import "ServerAPIClient.h"

#import "AFJSONRequestOperation.h"


@interface WildPokemonController () {
 @private
  BOOL                  isReady_;
  BOOL                  isPokemonAppeared_;
  NSInteger             UID_;
  NSInteger             pokemonCounter_;
  NSMutableDictionary * locationInfo_;
}

@property (nonatomic, copy) NSMutableDictionary * locationInfo;

- (void)cleanDataWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext;
- (void)updateWildPokemon:(WildPokemon *)wildPokemon withData:(NSDictionary *)data;
- (NSNumber *)calculateGenderWithPokemonGenderRate:(PokemonGenderRate)pokemonGenderRate;
- (NSString *)calculateFourMovesWithMoves:(NSArray *)moves level:(NSInteger)level;
- (NSString *)calculateStatsWithBaseStats:(NSArray *)baseStats level:(NSInteger)level;
- (NSInteger)calculateEXPWithBaseEXP:(NSInteger)baseEXP level:(NSInteger)level;

- (void)generateWildPokemonWithLocationInfo:(NSDictionary *)locationInfo;
- (PokemonHabitat)parseHabitatWithLocationType:(NSString *)locationType;
//- (NSArray *)filterSIDs:(NSArray *)SIDs;

@end


@implementation WildPokemonController

@synthesize locationInfo = locationInfo_;

// Singleton
static WildPokemonController * wildPokemonController_ = nil;
+ (WildPokemonController *)sharedInstance {
  if (wildPokemonController_ != nil)
    return wildPokemonController_;
  
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    wildPokemonController_ = [[WildPokemonController alloc] init];
  });
  return wildPokemonController_;
}

- (void)dealloc
{
  self.locationInfo = nil;
  
  [super dealloc];
}

- (id)init {
  if (self = [super init]) {
    isReady_           = NO;
    isPokemonAppeared_ = NO;
    UID_               = 0;
    pokemonCounter_    = 0;
  }
  return self;
}

#pragma mark - Public Methods

- (void)updateForCurrentRegion {
  // Success Block Method
  void (^success)(AFHTTPRequestOperation *, id) = ^(AFHTTPRequestOperation *operation, id JSON) {
    NSManagedObjectContext * managedObjectContext =
      [(AppDelegate *)[[UIApplication sharedApplication] delegate] managedObjectContext];
    
    // Clean data for model:|WildPokemon| & reset pokemonCounter to 0
    [self cleanDataWithManagedObjectContext:managedObjectContext];
    pokemonCounter_ = 0;
    
    // Get JSON Data Array from HTTP Response
    NSArray * wildPokemons = [JSON valueForKey:@"wpms"];
    // Update the data for |WildPokePokemon|
    for (NSDictionary * wildPokemonData in wildPokemons) {
      WildPokemon * wildPokemon;
      wildPokemon = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([WildPokemon class])
                                                  inManagedObjectContext:managedObjectContext];
      // Update data for current |wildPokemon|
      [self updateWildPokemon:wildPokemon withData:wildPokemonData];
    }
    
    NSError * error;
    if (! [managedObjectContext save:&error])
      NSLog(@"!!! Couldn't save data to %@", NSStringFromClass([WildPokemon class]));
    NSLog(@"...Update |%@| data done...", [WildPokemon class]);
    
    // If a Wild Pokemon Appeared already, fetch data for it
    if (isPokemonAppeared_)
      [self generateWildPokemonWithLocationInfo:self.locationInfo];
  };
  
  // Failure Block Method
  void (^failure)(AFHTTPRequestOperation *, NSError *) = ^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"!!! ERROR: %@", error);
  };
  
  // Update data via |ServerAPIClient|
  [[ServerAPIClient sharedInstance] updateWildPokemonsForCurrentRegion:nil
                                                               success:success
                                                               failure:failure];
}

// Update data for Wild Pokemon at current location
- (void)updateAtLocation:(CLLocation *)location {
  isPokemonAppeared_ = YES;
  isReady_           = NO;
  
  NSLog(@"......|%@| - UPDATING AT LOCATION......", [self class]);
  ///Fetch Data from server
  // Success Block
  void (^success)(NSURLRequest *, NSHTTPURLResponse *, id);
  success = ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
    // Set data
    NSLog(@"status: %@", [JSON valueForKey:@"status"]);
    // Check STATUS CODE
    //
    //               OK: indicates that no errors occurred;
    //                   the place was successfully detected and at least one result was returned.
    //    UNKNOWN_ERROR: indicates a server-side error; trying again may be successful.
    //     ZERO_RESULTS: indicates that the reference was valid but no longer refers to a valid result.
    //                   This may occur if the establishment is no longer in business.
    // OVER_QUERY_LIMIT: indicates that you are over your quota.
    //   REQUEST_DENIED: indicates that your request was denied, generally because of lack of a sensor parameter.
    //  INVALID_REQUEST: generally indicates that the query (reference) is missing.
    //
    if (! [[JSON valueForKey:@"status"] isEqualToString:@"OK"]) {
      NSLog(@"!!! ERROR: Response STATUS is NOT OK");
      return;
    }
    
    // The GeocoderResults object literal represents a single Geocoding result
    //   and is an object of the following form:
    //
    // results[]: {
    //   types[]: string,
    //   formatted_address: string,
    //   address_components[]: {
    //     short_name: string,
    //     long_name: string,
    //     types[]: string
    //   },
    //   geometry: {
    //     location: LatLng,
    //     location_type: GeocoderLocationType
    //     viewport: LatLngBounds,
    //     bounds: LatLngBounds
    //   }
    // }
    //
    NSLog(@"Setting data for |locationInfo|....");
    NSDictionary * results  = [[JSON valueForKey:@"results"] objectAtIndex:0];
    
    NSDictionary * locationInfo;
    locationInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                    [[results valueForKey:@"types"] objectAtIndex:0], @"type", nil];
    
    // Generate Wild Pokemon with the data of |locationInfo|
    [self generateWildPokemonWithLocationInfo:locationInfo];
    [locationInfo release];
    results  = nil;
  };
  
  // Failure Block
  void (^failure)(NSURLRequest *, NSHTTPURLResponse *, NSError *, id);
  failure = ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
    NSLog(@"!!! ERROR: %@", error);
  };
  
  // Fetch Data from server
  NSString * requestURL =
    [NSString stringWithFormat:@"http://maps.googleapis.com/maps/api/geocode/json?latlng=%f,%f&sensor=true",
      location.coordinate.latitude, location.coordinate.longitude];
  NSLog(@"%@", requestURL);
  NSURL * url = [[NSURL alloc] initWithString:requestURL];
  NSURLRequest * request = [[NSURLRequest alloc] initWithURL:url];
  [url release];
  AFJSONRequestOperation * operation =
    [AFJSONRequestOperation JSONRequestOperationWithRequest:request
                                                    success:success
                                                    failure:failure];
  [request release];
  [operation start];
}

// Only YES if data for new appeared Pokemon generated done
- (BOOL)isReady {
  return isReady_;
}

// Return UID for appeared Pokemon to generate Wild Pokemon for Game Battle Scene
- (NSInteger)appearedPokemonUID {
//  return UID_;
  return 1;
}

#pragma mark - Private Methods
#pragma mark - For updating

// Clean Wild Pokemon's data
- (void)cleanDataWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext {
  NSFetchRequest * fetchRequest = [[NSFetchRequest alloc] init];
  NSEntityDescription * entity = [NSEntityDescription entityForName:NSStringFromClass([WildPokemon class])
                                             inManagedObjectContext:managedObjectContext];
  [fetchRequest setEntity:entity];
  NSError * error;
  NSArray * wildPokemons = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
  [fetchRequest release];
  
  for (WildPokemon *wildPokemon in wildPokemons)
    [managedObjectContext deleteObject:wildPokemon];
  
  if (! [managedObjectContext save:&error])
    NSLog(@"!!! Couldn't save data to %@", NSStringFromClass([WildPokemon class]));
  NSLog(@"...Clean |%@| data done...", [WildPokemon class]);
}

// Update data for WildPokemon entity
- (void)updateWildPokemon:(WildPokemon *)wildPokemon withData:(NSDictionary *)data {
  // Update basic data fetched from server
  id SID = [data valueForKey:@"id"]; // id:SID
  wildPokemon.uid         = [NSNumber numberWithInt:++pokemonCounter_];
  wildPokemon.sid         = SID;
  wildPokemon.status      = [NSNumber numberWithInt:kPokemonStatusNormal];
  wildPokemon.level       = [data valueForKey:@"lv"]; // lv:Level
  NSInteger level = [wildPokemon.level intValue];
  
  // Fetch Pokemon entity with |sid|
  Pokemon * pokemon = [Pokemon queryPokemonDataWithID:[SID intValue]];
  wildPokemon.pokemon = pokemon; // Relationship betweent Pokemon & WildPokemon
  
  // |gender|
  wildPokemon.gender = [self calculateGenderWithPokemonGenderRate:[pokemon.genderRate intValue]];
  
  // |fourMoves|
  wildPokemon.fourMoves = [self calculateFourMovesWithMoves:[pokemon.moves componentsSeparatedByString:@","] level:level];
  
  // |maxStats| & |hp|
  NSString * maxStats  = [self calculateStatsWithBaseStats:[pokemon.baseStats componentsSeparatedByString:@","] level:level];
  wildPokemon.maxStats = maxStats;
  wildPokemon.hp       = [NSNumber numberWithInt:[[[maxStats componentsSeparatedByString:@","] objectAtIndex:0] intValue]];
  maxStats = nil;
  
  // |exp| & |toNextLevel|
  // Calculate EXP based on Level Formular with value:|level|
  wildPokemon.exp         = [NSNumber numberWithInt:[pokemon expAtLevel:level]];
  wildPokemon.toNextLevel = [NSNumber numberWithInt:[pokemon expToNextLevel:(level + 1)]];
  
  pokemon = nil;
}

// Calculate |gender| based on |pokemonGenderRate|
// 0:Female 1:Male 2:Genderless
- (NSNumber *)calculateGenderWithPokemonGenderRate:(PokemonGenderRate)pokemonGenderRate {
  NSInteger gender;
  if      (pokemonGenderRate == kPokemonGenderRateAlwaysFemale) gender = 0;
  else if (pokemonGenderRate == kPokemonGenderRateAlwaysMale)   gender = 1;
  else if (pokemonGenderRate == kPokemonGenderRateGenderless)   gender = 2;
  else {
    float randomValue = arc4random() % 1000 / 10; // Random value for calculating
    float genderRate = 25 * ((pokemonGenderRate == kPokemonGenderRateFemaleOneEighth) ? .5f : (pokemonGenderRate - 2));
    gender = randomValue < genderRate ? 0 : 1;
  }
  return [NSNumber numberWithInt:gender];
}

// Calculate |fourMoves| based on |moves| & |leve|
- (NSString *)calculateFourMovesWithMoves:(NSArray *)moves level:(NSInteger)level {
  NSInteger moveCount = [moves count];
  // Get the last learned Move index
  NSInteger lastLearnedMoveIndex = 0;
  NSMutableArray * fourMovesID = [[NSMutableArray alloc] init];
  for (int i = 0; i < moveCount - 1; i += 2) {
    if ([[moves objectAtIndex:i] intValue] > level)
      break;
    // Remove the first Move when there're four Moves learned
    if ([fourMovesID count] == 4)
      [fourMovesID removeObjectAtIndex:0];
    // Push new Move ID
    [fourMovesID addObject:[moves objectAtIndex:(i + 1)]];
    ++lastLearnedMoveIndex;
  }
  // Fetch |fourMoves| with |fourMovesID|
  NSArray * fourMoves = [Move queryFourMovesDataWithIDs:fourMovesID];
  [fourMovesID release];
  
  NSMutableString * fourMovesInString = [NSMutableString string];
  moveCount = 0;
  for (Move * move in fourMoves) {
    if (moveCount != 0) [fourMovesInString appendString:@","];
    ++moveCount;
    [fourMovesInString appendString:[NSString stringWithFormat:@"%d,%d,%d",
                                     [move.sid intValue], [move.basePP intValue], [move.basePP intValue]]];
  }
  fourMoves = nil;
  return fourMovesInString;
}

// Calculate |stats| based on |baseStats|
- (NSString *)calculateStatsWithBaseStats:(NSArray *)baseStats level:(NSInteger)level {
  NSInteger statHP        = [[baseStats objectAtIndex:0] intValue];
  NSInteger statAttack    = [[baseStats objectAtIndex:1] intValue];
  NSInteger statDefense   = [[baseStats objectAtIndex:2] intValue];
  NSInteger statSpAttack  = [[baseStats objectAtIndex:3] intValue];
  NSInteger statSpDefense = [[baseStats objectAtIndex:4] intValue];
  NSInteger statSpeed     = [[baseStats objectAtIndex:5] intValue];
  
  // Calculate the stats
  statHP        += 3 * level;
  statAttack    += level;
  statDefense   += level;
  statSpAttack  += level;
  statSpDefense += level;
  statSpeed     += level;
  
  return [NSString stringWithFormat:@"%d,%d,%d,%d,%d,%d",
          statHP, statAttack, statDefense, statSpAttack, statSpDefense, statSpeed];
}

// Calculate EXP based on |baseEXP| with |level|
// y:return value:|result|
// x:|level|
//
// TODO:
//   The formular is not suit now!!
//
- (NSInteger)calculateEXPWithBaseEXP:(NSInteger)baseEXP level:(NSInteger)level {
  NSInteger result;
  result = (10000000 - 100) / (100 - 1) * level + baseEXP;
  return result;
}

#pragma mark - For Generating

// Generate Wild Pokemon with location info
- (void)generateWildPokemonWithLocationInfo:(NSDictionary *)locationInfo {
  NSLog(@"|%@| - |generateWildPokemonWithLocationInfo:| - locationInfo::%@", [self class], locationInfo);
  
  // Parse the habitat type from current location type
  PokemonHabitat     habitat = [self parseHabitatWithLocationType:[locationInfo valueForKey:@"type"]];
  NSArray      * pokemonSIDs = [Pokemon SIDsForHabitat:habitat];
  WildPokemon  * wildPokemon = [[WildPokemon queryPokemonsWithSIDs:pokemonSIDs fetchLimit:1] lastObject];
  NSLog(@"Habitat:%d - PokemonSIDs:<< %@ >> - WildPokemon:%@",
        habitat, [pokemonSIDs componentsJoinedByString:@","], wildPokemon);
  
  // If no Wild Pokemon data matched, update all data for current region
  if (wildPokemon == nil) {
    // Save location info data
    self.locationInfo = [locationInfo mutableCopy];
    [self updateForCurrentRegion];
    return;
  }
  
  // Set data
  UID_               = [wildPokemon.uid intValue];
  isReady_           = YES;
  isPokemonAppeared_ = NO;
}

// Parse habitat with the location type
/*
 kPokemonHabitatCave         = 1,
 kPokemonHabitatForest       = 2,
 kPokemonHabitatGrassland    = 3,
 kPokemonHabitatMountain     = 4,
 kPokemonHabitatRare         = 5, // Mean "Unknow"
 kPokemonHabitatRoughTerrain = 6,
 kPokemonHabitatSea          = 7,
 kPokemonHabitatUrban        = 8,
 kPokemonHabitatWatersEdge   = 9
 */
/*
              street_address: indicates a precise street address.
                       route: indicates a named route (such as "US 101").
                intersection: indicates a major intersection, usually of two major roads.
                   political: indicates a political entity. Usually, this type indicates a polygon
                              of some civil administration.
                     country: indicates the national political entity, and is typically the highest
                              order type returned by the Geocoder.
 administrative_area_level_1: indicates a first-order civil entity below the country level.
                              Within the United States, these administrative levels are states.
                              Not all nations exhibit these administrative levels.
 administrative_area_level_2: indicates a second-order civil entity below the country level.
                              Within the United States, these administrative levels are counties.
                              Not all nations exhibit these administrative levels.
 administrative_area_level_3: indicates a third-order civil entity below the country level.
                              This type indicates a minor civil division.
                              Not all nations exhibit these administrative levels.
             colloquial_area: indicates a commonly-used alternative name for the entity.
                    locality: indicates an incorporated city or town political entity.
                 sublocality: indicates an first-order civil entity below a locality.
                neighborhood: indicates a named neighborhood.
                     premise: indicates a named location, usually a building or collection of buildings
                              with a common name
                  subpremise: indicates a first-order entity below a named location, usually a singular
                              building within a collection of buildings with a common name.
                 postal_code: indicates a postal code as used to address postal mail within the country.
             natural_feature: indicates a prominent natural feature.
                     airport: indicates an airport.
                        park: indicates a named park.
 */
- (PokemonHabitat)parseHabitatWithLocationType:(NSString *)locationType {
  NSLog(@"locationType:%@", locationType);
  PokemonHabitat habitat;
  if ([locationType isEqualToString:@"premise"] || [locationType isEqualToString:@"subpremise"])
    habitat = kPokemonHabitatCave;
  else if ([locationType isEqualToString:@"natural_feature"])
    habitat = kPokemonHabitatForest;
  else if ([locationType isEqualToString:@"park"])
    habitat = kPokemonHabitatGrassland;
  else if ([locationType isEqualToString:@"airport"])
    habitat = kPokemonHabitatMountain;
  else if ([locationType isEqualToString:@"colloquial_area"])
    habitat = kPokemonHabitatRoughTerrain;
  else if ([locationType isEqualToString:@""])
    habitat = kPokemonHabitatSea;
  else if ([locationType isEqualToString:@"street_address"] ||
           [locationType isEqualToString:@"route"] ||
           [locationType isEqualToString:@"intersection"] ||
           [locationType isEqualToString:@"locality"] ||
           [locationType isEqualToString:@"sublocality"] ||
           [locationType isEqualToString:@"political"] ||
           [locationType isEqualToString:@"country"] ||
           [locationType isEqualToString:@"administrative_area_level_1"] ||
           [locationType isEqualToString:@"administrative_area_level_2"] ||
           [locationType isEqualToString:@"administrative_area_level_3"])
    habitat = kPokemonHabitatUrban;
  else if ([locationType isEqualToString:@"neighborhood"])
    habitat = kPokemonHabitatWatersEdge;
  else
    habitat = kPokemonHabitatRare;
  
  return habitat;
}

/*/ Filter Pokemon SIDs for current fetched Wild Pokemon Grounp
- (NSArray *)filterSIDs:(NSArray *)SIDs {
  NSLog(@"ORIGINAL SIDs:%@", SIDs);
  if (SIDs == nil || [SIDs count] == 0)
    return nil;
  
  NSMutableArray * newSIDs = [NSMutableArray array];
  for (id SID in SIDs) {
  }
  NSLog(@"NEW SIDs:%@", newSIDs);
  return newSIDs;
}*/

@end
